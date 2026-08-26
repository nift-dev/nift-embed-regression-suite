// CP18 part B: C++ Engine raw render + repeated/server workload.
// Workload matches the Go/C#/Node/Python benches: <p>$[site]</p> in <main>@content</main>.
#include <nift/nift.h>
#include <chrono>
#include <algorithm>
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
    // Warm-up round (unreported) so JIT/scheduling settles before measuring.
    for (int i = 0; i < n; ++i) engine.render(page, tpl);
    double raw_samples[rounds], req_samples[rounds];
    for (int r = 0; r < rounds; ++r) {
        auto start = std::chrono::steady_clock::now();
        for (int i = 0; i < n; ++i) {  // raw: no request Context, engine-default binding
            auto rr = engine.render(page, tpl);
            if (!rr.ok()) { std::fprintf(stderr, "%s\n", rr.error().message.c_str()); return 1; }
        }
        raw_samples[r] = std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count() / n;
        start = std::chrono::steady_clock::now();
        for (int i = 0; i < 1000; ++i) {  // request-loop: fresh Context per request
            nift::Context c;
            c.set("who", std::string("w"));
            auto rr = engine.render(page, tpl, c);
            if (!rr.ok()) return 1;
        }
        req_samples[r] = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }
    std::sort(raw_samples, raw_samples + rounds);
    std::sort(req_samples, req_samples + rounds);
    std::printf("cpp raw=%.0f ns/render request-loop=%.0f ms/1000 rounds=%d\n",
                raw_samples[rounds / 2], req_samples[rounds / 2], rounds);
    return 0;
}
