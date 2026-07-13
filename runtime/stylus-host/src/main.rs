use proof_forge_stylus_host::{Host, TokenHost};

fn main() {
    if std::env::args().nth(1).as_deref() == Some("token") {
        println!("{}", TokenHost::default().normalized_scenario_json());
        return;
    }
    let mut host = Host::default();
    host.initialize();
    host.increment().expect("Counter increment must succeed");
    host.get();
    println!("{}", host.normalized_json());
}
