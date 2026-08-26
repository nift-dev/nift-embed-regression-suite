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
    auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < n; ++i) {
        auto r = engine.render(page, tpl, nift::Context{});
        if (!r.ok()) { std::fprintf(stderr, "%s\n", r.error().message.c_str()); return 1; }
    }
    auto raw = std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count() / n;
    start = std::chrono::steady_clock::now();
    for (int i = 0; i < 1000; ++i) {
        nift::Context c;
        c.set("who", std::string("w"));
        auto r = engine.render(page, tpl, c);
        if (!r.ok()) return 1;
    }
    auto server = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    std::printf("cpp raw=%.0f ns/render server=%.0f ms/1000\n", raw, server);
    return 0;
}
