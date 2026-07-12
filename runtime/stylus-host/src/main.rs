use proof_forge_stylus_host::Host;

fn main() {
    let mut host = Host::default();
    host.initialize();
    host.increment().expect("Counter increment must succeed");
    host.get();
    println!("{}", host.normalized_json());
}
