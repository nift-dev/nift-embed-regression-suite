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
    const int n = 50000;
    const int rounds = 3;
    double raw_best = 1e300, req_best = 1e300;
    for (int r = 0; r < rounds; ++r) {
        auto start = std::chrono::steady_clock::now();
        for (int i = 0; i < n; ++i) {  // raw: no request Context, engine-default binding
            nift_render_result* res = nullptr;
            nift_engine_render(engine, &ps, &ts, nullptr, &res);
            nift_render_result_free(res);
        }
        double raw = std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count() / n;
        if (raw < raw_best) raw_best = raw;
        start = std::chrono::steady_clock::now();
        for (int i = 0; i < 1000; ++i) {  // request-loop: fresh Context per request
            nift_context* rc = nift_context_new();
            std::string who = "w";
            nift_context_set_string(rc, "who", 3, who.data(), who.size());
            nift_render_result* res = nullptr;
            nift_engine_render(engine, &ps, &ts, rc, &res);
            nift_render_result_free(res);
            nift_context_free(rc);
        }
        double req = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
        if (req < req_best) req_best = req;
    }
    nift_engine_free(engine);
    std::printf("cabi raw=%.0f ns/render request-loop=%.0f ms/1000 rounds=%d\n", raw_best, req_best, rounds);
    return 0;
}
