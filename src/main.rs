/* CLI program to manage devcontainers */

use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    /* check if the user has passed any arguments */
    if args.len() == 1 {
        println!("No arguments passed");
        std::process::exit(0);
    }
    let command = &args[1];

    match command.as_str() {
        "start" => start(),
        _ => println!("Unknown command"),
    }
}

fn start() {
    println!("Starting devcontainer");
}