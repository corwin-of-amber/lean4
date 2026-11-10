#include <cassert>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <fstream>
#include <sys/stat.h>
#include "runtime/posix_spawn.h"
using namespace lean;
using namespace lean::detail;
static int finish(spawned_process & child) {
    int status;
    assert(waitpid(child.release_pid(), &status, 0) > 0);
    assert(WIFEXITED(status));
    return WEXITSTATUS(status);
}
static std::string read_output(unique_fd & fd) {
    std::string text; char buffer[1024]; ssize_t n;
    while ((n = read(fd.get(), buffer, sizeof(buffer))) > 0) text.append(buffer, n);
    assert(n == 0);
    return text;
}
static size_t descriptors() {
    return std::distance(std::filesystem::directory_iterator("/proc/self/fd"), std::filesystem::directory_iterator());
}
int main() {
    setenv("LEAN_SPAWN_PARENT", "inherited", 1);
    posix_spawn_options o;
    o.command = "/bin/sh";
    o.args = {"-c", "printf '%s:%s' \"$LEAN_SPAWN_PARENT\" \"$EXTRA\""};
    o.output = PIPED;
    o.env = {{"EXTRA", "added"}};
    auto child = spawn_posix(o);
    assert(read_output(child.output) == "inherited:added"); assert(finish(child) == 0);
    o.inherit_env = false;
    child = spawn_posix(o);
    assert(read_output(child.output) == ":added"); assert(finish(child) == 0);
    o.inherit_env = true; o.env = {{"LEAN_SPAWN_PARENT", std::nullopt}};
    child = spawn_posix(o);
    assert(read_output(child.output) == ":"); assert(finish(child) == 0);
    char directory[] = "/tmp/lean-spawn-path-XXXXXX";
    assert(mkdtemp(directory));
    auto program = std::filesystem::path(directory) / "lean-path-test";
    { std::ofstream file(program); file << "#!/bin/sh\nprintf custom-path"; }
    assert(chmod(program.c_str(), 0700) == 0);
    o.command = "lean-path-test"; o.args = {}; o.env = {{"PATH", directory}};
    child = spawn_posix(o);
    assert(read_output(child.output) == "custom-path"); assert(finish(child) == 0);
    o.cwd = directory; o.env = {{"PATH", "."}};
    child = spawn_posix(o);
    assert(read_output(child.output) == "custom-path"); assert(finish(child) == 0);
    std::filesystem::remove_all(directory);
    o.command = "/bin/sh"; o.env.clear();
    o.cwd = "/tmp"; o.args = {"-c", "pwd"};
    child = spawn_posix(o);
    assert(read_output(child.output) == "/tmp\n"); assert(finish(child) == 0);
    o.cwd.reset(); o.input = PIPED; o.args = {"-c", "cat; printf err >&2; exit 7"}; o.error = PIPED;
    child = spawn_posix(o);
    assert(write(child.input.get(), "hello", 5) == 5); child.input.reset();
    assert(read_output(child.output) == "hello"); assert(read_output(child.error) == "err"); assert(finish(child) == 7);
    o.input = NUL; o.output = NUL; o.error = NUL; o.args = {"-c", "read x && exit 1; printf ignored; printf ignored >&2"};
    child = spawn_posix(o); assert(finish(child) == 0);
#ifdef POSIX_SPAWN_SETSID
    o.setsid = true; o.args = {"-c", "sleep 10"};
    { auto session = spawn_posix(o); assert(getsid(session.pid()) == session.pid()); }
#endif
    o.setsid = false; o.command = "/nonexistent-lean-spawn-test"; o.input = PIPED; o.output = PIPED;
    auto before = descriptors();
    for (int i = 0; i < 100; ++i) {
        try { auto missing = spawn_posix(o); assert(false); }
        catch (int error) { assert(error == ENOENT); }
    }
    assert(descriptors() == before);
    o.command = "/bin/sh"; o.cwd = "/nonexistent-lean-spawn-directory";
    try { auto missing = spawn_posix(o); assert(false); }
    catch (int error) { assert(error == ENOENT); }
    std::cout << "POSIX spawn ownership and option tests passed\n";
}
