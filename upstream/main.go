package main
import (
    "fmt"
    "net/http"
    "runtime"
)
func main() {
    runtime.GOMAXPROCS(runtime.NumCPU())
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "text/plain")
        fmt.Fprint(w, "OK")
    })
    fmt.Println("Upstream starting on :8080...")
    http.ListenAndServe(":8080", nil)
}
