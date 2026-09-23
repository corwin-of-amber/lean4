// crctool -- compute a CRC over every line of a file.
//
//   crctool [options] <width> <poly> [file]
//
// <width>  register width in bits, 8..64
// <poly>   feedback polynomial, omitting the implicit x^width term.
//          Accepts 0x hex, 0 octal, or decimal.
// [file]   input file, one string per line; "-" or omitted means stdin.
//
// Options:
//   -i HEX   initial register value (default: all ones)
//   -c       check for collisions and report them; implies -q
//   -q       suppress the per-line output
//   -h       this help
//
// Trailing CR/LF is stripped. Empty lines are skipped. Embedded NUL bytes
// are hashed like any other byte.
//
// Build:
//   c++ -std=c++17 crazy/dyntable/crc.c crazy/dyntable/crc_smoke.cpp \
//       crazy/dyn.o -Wl,-undefined,dynamic_lookup
#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <istream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "crc.h"

namespace {

struct Entry {
    std::uint64_t value;
    std::string   text;
    std::size_t   lineno;
};

struct UsageError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

void usage(std::ostream &out, std::string_view argv0)
{
    out << "usage: " << argv0 << " [-i HEX] [-c] [-q] <width> <poly> [file]\n"
        << "  width   register width in bits, 8..64\n"
        << "  poly    feedback polynomial, implicit x^width term omitted\n"
        << "  file    one string per line; \"-\" or omitted reads stdin\n"
        << "  -i HEX  initial register value (default: all ones)\n"
        << "  -c      report collisions (implies -q)\n"
        << "  -q      no per-line output\n";
}

std::uint64_t parse_u64(std::string_view text, std::string_view what)
{
    const std::string s(text);
    std::size_t pos = 0;
    std::uint64_t v = 0;
    try {
        v = std::stoull(s, &pos, 0);
    } catch (const std::exception &) {
        throw UsageError("could not parse " + std::string(what) + " \"" + s + "\"");
    }
    if (pos != s.size())
        throw UsageError("trailing junk in " + std::string(what) + " \"" + s + "\"");
    return v;
}

std::string to_hex(std::uint64_t v, int digits)
{
    static const char *D = "0123456789ABCDEF";
    std::string s(static_cast<std::size_t>(digits), '0');
    for (int i = digits - 1; i >= 0; --i, v >>= 4)
        s[static_cast<std::size_t>(i)] = D[v & 0xF];
    return s;
}

std::string to_hex(std::uint64_t v)
{
    int digits = 1;
    for (std::uint64_t t = v; t >= 16; t >>= 4) ++digits;
    return to_hex(v, digits);
}

struct entry { uint32_t k; void *p; };
extern "C" struct entry __dyn_table[];


int run(const std::vector<std::string_view> &args)
{
    bool check = false, quiet = false, have_init = false;
    std::uint64_t init = 0;
    std::size_t i = 1;

    for (; i < args.size() && args[i].size() > 1 && args[i][0] == '-'; ++i) {
        const std::string_view opt = args[i];
        if (opt == "--") { ++i; break; }
        if (opt == "-h" || opt == "--help") {
            usage(std::cout, args[0]);
            return 0;
        } else if (opt == "-c") {
            check = quiet = true;
        } else if (opt == "-q") {
            quiet = true;
        } else if (opt == "-i") {
            if (i + 1 >= args.size())
                throw UsageError("-i needs a numeric argument");
            init = parse_u64(args[++i], "init value");
            have_init = true;
        } else {
            throw UsageError("unknown option " + std::string(opt));
        }
    }

    const std::size_t positional = args.size() - i;
    if (positional < 2 || positional > 3)
        throw UsageError("expected <width> <poly> [file]");

    const std::uint64_t width64 = parse_u64(args[i], "width");
    if (width64 < 8 || width64 > 64)
        throw UsageError("width must be an integer in 8..64");
    const auto width = static_cast<unsigned>(width64);

    const std::uint64_t mask =
        (width == 64) ? UINT64_MAX : ((std::uint64_t{1} << width) - 1);
    const int digits = static_cast<int>((width + 3) / 4);

    const std::uint64_t poly = parse_u64(args[i + 1], "polynomial");
    if (poly > mask)
        throw UsageError("polynomial 0x" + to_hex(poly) + " does not fit in "
                         + std::to_string(width) + " bits (the x^"
                         + std::to_string(width)
                         + " term is implicit and must be omitted)");
    if ((poly & 1) == 0)
        std::cerr << args[0] << ": warning: polynomial has no constant term, so "
                     "trailing NUL/zero bytes cannot affect the result\n";
    if (have_init && init > mask)
        throw UsageError("init value does not fit in " + std::to_string(width)
                         + " bits");

    const std::string path(positional == 3 ? args[i + 2] : "-");
    std::ifstream file;
    if (path != "-") {
        file.open(path, std::ios::binary);
        if (!file) {
            std::cerr << args[0] << ": " << path << ": "
                      << std::strerror(errno) << '\n';
            return 1;
        }
    }
    std::istream &in = (path == "-") ? std::cin : file;

    crc_t crc;
    crc_init(&crc, width, poly, have_init ? init : mask);

    std::vector<Entry> entries;
    std::string line;
    std::size_t lineno = 0, count = 0;

    while (std::getline(in, line)) {
        ++lineno;
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        if (line.empty())
            continue;
        ++count;

        const std::uint64_t v = crc_bytes(&crc, line.data(), line.size());

        for (int i = 0; i < 100000; i++) {
            auto& e = __dyn_table[i];
            if (e.k == 0) {
                std::cout << "not found (" << i << ")" << std::endl;
                break;
            }
            if (e.k == v)  {
                std::cout << "found at " << i << std::endl;
                break;
            }
        }
        //entries.push_back({v, line, lineno});
    }

    if (in.bad()) {
        std::cerr << args[0] << ": " << path << ": read error\n";
        return 1;
    }

    return 0;

    /*

    if (!check)
        return 0;

    std::sort(entries.begin(), entries.end(),
              [](const Entry &a, const Entry &b) { return a.value < b.value; });

    std::size_t groups = 0, extra = 0;
    for (auto it = entries.begin(); it != entries.end(); ) {
        const auto end = std::find_if(it, entries.end(), [&](const Entry &e) {
            return e.value != it->value;
        });
        if (end - it > 1) {
            ++groups;
            extra += static_cast<std::size_t>(end - it) - 1;
            std::cerr << "collision at " << to_hex(it->value, digits) << ':';
            for (auto k = it; k != end; ++k)
                std::cerr << ' ' << k->text << " (line " << k->lineno << ')';
            std::cerr << '\n';
        }
        it = end;
    }

    std::cout << count << " strings, " << (count - extra)
              << " distinct states, " << groups << " colliding group"
              << (groups == 1 ? "" : "s") << '\n';

    return groups ? 1 : 0;
    */
}

}  // namespace

int main(int argc, char **argv)
{
    std::ios::sync_with_stdio(false);
    const std::vector<std::string_view> args(argv, argv + argc);
    try {
        return run(args);
    } catch (const UsageError &e) {
        std::cerr << args[0] << ": " << e.what() << '\n';
        usage(std::cerr, args[0]);
        return 2;
    } catch (const std::exception &e) {
        std::cerr << args[0] << ": " << e.what() << '\n';
        return 1;
    }
}
