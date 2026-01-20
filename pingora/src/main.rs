use pingora::prelude::*;
use async_trait::async_trait;

struct MyProxy;
#[async_trait]
impl ProxyHttp for MyProxy {
    type CTX = ();
    fn new_ctx(&self) -> Self::CTX {}
    async fn upstream_peer(&self, _session: &mut Session, _ctx: &mut Self::CTX) -> Result<Box<HttpPeer>> {
        Ok(Box::new(HttpPeer::new(("127.0.0.1", 8080), false, "".to_string())))
    }
}

fn main() {
    let mut server = Server::new(None).unwrap();
    server.bootstrap();
    let mut proxy = http_proxy_service(&server.configuration, MyProxy);
    proxy.add_tcp("0.0.0.0:8082");
    server.add_service(proxy);
    server.run_forever();
}
