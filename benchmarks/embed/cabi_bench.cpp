// CP18 part B: C ABI raw render + repeated/server workload.
#include <nift/c_abi.h>
#include <chrono>
#include <cstdio>
#include <string>

int main() {
    nift_engine* engine = nift_engine_new();
    std::string root = "/";
    nift_engine_set_root(engine, root.data(), root.size());
    std::string page = "<p>$[site]</p>";
    std::string tpl = "<main>@content</main>";
    nift_source ps{NIFT_SOURCE_TEXT, page.data(), page.size(), nullptr, 0};
    nift_source ts{NIFT_SOURCE_TEXT, tpl.data(), tpl.size(), nullptr, 0};
    std::string site = "nift";
    nift_engine_set_string(engine, "site", 4, site.data(), site.size());
    nift_context* c = nift_context_new();
    const int n = 50000;
    auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < n; ++i) {
        nift_render_result* r = nullptr;
        nift_engine_render(engine, &ps, &ts, c, &r);
        nift_render_result_free(r);
    }
    auto raw = std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count() / n;
    // Server workload: 1000 repeated renders, each with a fresh request context.
    auto start2 = std::chrono::steady_clock::now();
    for (int i = 0; i < 1000; ++i) {
        nift_context* rc = nift_context_new();
        std::string who = "w";
        nift_context_set_string(rc, "who", 3, who.data(), who.size());
        nift_render_result* r = nullptr;
        nift_engine_render(engine, &ps, &ts, rc, &r);
        nift_render_result_free(r);
        nift_context_free(rc);
    }
    auto server = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start2).count();
    nift_context_free(c);
    nift_engine_free(engine);
    std::printf("cabi raw=%.0f ns/render server=%.0f ms/1000\n", raw, server);
    return 0;
}
