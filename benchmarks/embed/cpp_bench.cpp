// CP18 part B: C++ Engine raw render + repeated/server workload.
// Workload matches the Go/C#/Node/Python benches: <p>$[site]</p> in <main>@content</main>.
#include <nift/nift.h>
#include <chrono>
#include <cstdio>
#include <string>

int main() {
    nift::Engine engine;
    engine.set_root("/");
    engine.set("site", "nift");
    nift::Source page = nift::Source::text("<p>$[site]</p>");
    nift::Source tpl = nift::Source::text("<main>@content</main>");
    const int n = 50000;
    const int rounds = 3;
    double raw_best = 1e300, req_best = 1e300;
    for (int r = 0; r < rounds; ++r) {
        auto start = std::chrono::steady_clock::now();
        for (int i = 0; i < n; ++i) {  // raw: no request Context, engine-default binding
            auto rr = engine.render(page, tpl);
            if (!rr.ok()) { std::fprintf(stderr, "%s\n", rr.error().message.c_str()); return 1; }
        }
        double raw = std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count() / n;
        if (raw < raw_best) raw_best = raw;
        start = std::chrono::steady_clock::now();
        for (int i = 0; i < 1000; ++i) {  // request-loop: fresh Context per request
            nift::Context c;
            c.set("who", std::string("w"));
            auto rr = engine.render(page, tpl, c);
            if (!rr.ok()) return 1;
        }
        double req = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
        if (req < req_best) req_best = req;
    }
    std::printf("cpp raw=%.0f ns/render request-loop=%.0f ms/1000 rounds=%d\n", raw_best, req_best, rounds);
    return 0;
}
