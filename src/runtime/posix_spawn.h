/*
Copyright (c) 2026 Emilio Jesus Gallego Arias. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
*/
#pragma once
#include <cerrno>
#include <fcntl.h>
#include <map>
#include <optional>
#include <spawn.h>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include <utility>
#include <vector>
#include "runtime/process.h"

extern "C" { extern char ** environ; }

namespace lean {
namespace detail {
inline void check_spawn(int error) { if (error) throw error; }

class unique_fd {
    int m_fd = -1;
public:
    unique_fd() = default;
    explicit unique_fd(int fd) : m_fd(fd) {}
    unique_fd(unique_fd const &) = delete;
    unique_fd & operator=(unique_fd const &) = delete;
    unique_fd(unique_fd && other) noexcept : m_fd(other.release()) {}
    unique_fd & operator=(unique_fd && other) noexcept {
        if (this != &other) { reset(); m_fd = other.release(); }
        return *this;
    }
    ~unique_fd() { reset(); }
    int get() const { return m_fd; }
    int release() { return std::exchange(m_fd, -1); }
    void reset() { if (m_fd >= 0) close(release()); }
};

class spawn_actions {
public:
    posix_spawn_file_actions_t value;
    spawn_actions() { check_spawn(posix_spawn_file_actions_init(&value)); }
    spawn_actions(spawn_actions const &) = delete;
    spawn_actions & operator=(spawn_actions const &) = delete;
    ~spawn_actions() { posix_spawn_file_actions_destroy(&value); }
};

class spawn_attributes {
public:
    posix_spawnattr_t value;
    spawn_attributes() { check_spawn(posix_spawnattr_init(&value)); }
    spawn_attributes(spawn_attributes const &) = delete;
    spawn_attributes & operator=(spawn_attributes const &) = delete;
    ~spawn_attributes() { posix_spawnattr_destroy(&value); }
};

struct posix_spawn_options {
    std::string command;
    std::vector<std::string> args;
    std::optional<std::string> cwd;
    std::vector<std::pair<std::string, std::optional<std::string>>> env;
    bool inherit_env = true;
    bool setsid = false;
    stdio input = INHERIT, output = INHERIT, error = INHERIT;
};

class spawned_process {
    pid_t m_pid = -1;
    bool m_setsid = false;
public:
    unique_fd input, output, error;
    spawned_process() = default;
    spawned_process(spawned_process const &) = delete;
    spawned_process & operator=(spawned_process const &) = delete;
    spawned_process(spawned_process && other) noexcept :
        m_pid(other.release_pid()), m_setsid(other.m_setsid),
        input(std::move(other.input)), output(std::move(other.output)), error(std::move(other.error)) {}
    spawned_process & operator=(spawned_process && other) noexcept {
        if (this != &other) {
            reset(); m_pid = other.release_pid(); m_setsid = other.m_setsid;
            input = std::move(other.input); output = std::move(other.output); error = std::move(other.error);
        }
        return *this;
    }
    ~spawned_process() { reset(); }
    void reset() {
        if (m_pid > 0) {
            kill(m_setsid ? -m_pid : m_pid, SIGKILL);
            while (waitpid(m_pid, nullptr, 0) < 0 && errno == EINTR) {}
            m_pid = -1;
        }
    }
    void adopt(pid_t pid, bool setsid) { m_pid = pid; m_setsid = setsid; }
    pid_t pid() const { return m_pid; }
    pid_t release_pid() { return std::exchange(m_pid, -1); }
};

inline std::vector<char *> spawn_pointers(std::vector<std::string> & values) {
    std::vector<char *> pointers;
    for (auto & value : values) pointers.push_back(value.data());
    pointers.push_back(nullptr);
    return pointers;
}

inline spawned_process spawn_posix(posix_spawn_options const & options) {
    spawn_actions actions;
    spawn_attributes attributes;
    if (options.cwd) {
#if defined(__linux__) || defined(__APPLE__) || defined(__wasi__)
        check_spawn(posix_spawn_file_actions_addchdir_np(&actions.value, options.cwd->c_str()));
#else
        throw ENOTSUP;
#endif
    }
    if (options.setsid) {
#if defined(POSIX_SPAWN_SETSID) && !defined(__wasi__)
        check_spawn(posix_spawnattr_setflags(&attributes.value, POSIX_SPAWN_SETSID));
#else
        throw ENOTSUP;
#endif
    }
    std::map<std::string, std::string> environment;
    if (options.inherit_env && ::environ) {
        for (char ** entry = ::environ; *entry; ++entry) {
            std::string value(*entry);
            auto split = value.find('=');
            if (split != std::string::npos) environment[value.substr(0, split)] = value.substr(split + 1);
        }
    }
    for (auto const & entry : options.env) {
        if (entry.first.empty() || entry.first.find('=') != std::string::npos) throw EINVAL;
        if (entry.second) environment[entry.first] = *entry.second;
        else environment.erase(entry.first);
    }
    std::vector<std::string> env;
    for (auto const & entry : environment) env.push_back(entry.first + "=" + entry.second);
    auto envp = spawn_pointers(env);
    std::vector<std::string> args{options.command};
    args.insert(args.end(), options.args.begin(), options.args.end());
    auto argv = spawn_pointers(args);
    spawned_process child;
    std::vector<unique_fd> child_ends;
    auto redirect = [&](stdio mode, int target, bool input, unique_fd & parent) {
        if (mode == NUL) {
            check_spawn(posix_spawn_file_actions_addclose(&actions.value, target));
            check_spawn(posix_spawn_file_actions_addopen(&actions.value, target, "/dev/null", input ? O_RDONLY : O_WRONLY, 0));
        } else if (mode == PIPED) {
            int fds[2];
#if defined(__linux__) || defined(__wasi__)
            if (::pipe2(fds, O_CLOEXEC) < 0) throw errno;
#else
            if (::pipe(fds) < 0) throw errno;
#endif
            unique_fd read(fds[0]), write(fds[1]);
            for (unique_fd * fd : {&read, &write}) {
                if (fd->get() < 3) {
                    int duplicate = fcntl(fd->get(), F_DUPFD_CLOEXEC, 3);
                    if (duplicate < 0) throw errno;
                    *fd = unique_fd(duplicate);
                }
                if (fcntl(fd->get(), F_SETFD, FD_CLOEXEC) < 0) throw errno;
            }
            unique_fd & source = input ? read : write;
            parent = std::move(input ? write : read);
            check_spawn(posix_spawn_file_actions_addclose(&actions.value, parent.get()));
            check_spawn(posix_spawn_file_actions_adddup2(&actions.value, source.get(), target));
            check_spawn(posix_spawn_file_actions_addclose(&actions.value, source.get()));
            child_ends.push_back(std::move(source));
        }
    };
    redirect(options.input, STDIN_FILENO, true, child.input);
    redirect(options.output, STDOUT_FILENO, false, child.output);
    redirect(options.error, STDERR_FILENO, false, child.error);
    pid_t pid;
    auto execute = [&](std::string const & executable) {
        return posix_spawn(&pid, executable.c_str(), &actions.value, &attributes.value, argv.data(), envp.data());
    };
    if (options.command.find('/') != std::string::npos) {
        check_spawn(execute(options.command));
    } else {
        auto entry = environment.find("PATH");
        std::string search = entry == environment.end() ? "/bin:/usr/bin" : entry->second;
        bool denied = false;
        size_t start = 0;
        while (true) {
            auto end = search.find(':', start);
            auto directory = search.substr(start, end == std::string::npos ? end : end - start);
            auto executable = directory.empty() ? options.command : directory + "/" + options.command;
            int error = execute(executable);
            if (!error) break;
            if (error == EACCES) denied = true;
            else if (error != ENOENT && error != ENOTDIR) throw error;
            if (end == std::string::npos) throw denied ? EACCES : ENOENT;
            start = end + 1;
        }
    }
    child.adopt(pid, options.setsid);
    return child;
}
}
}
