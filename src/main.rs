/* CLI program to manage devcontainers */

mod susi {
    use std::{fs::File, io::Read};
    use serde_json::Value;


    // define public struct devcontaienr with public fields name and image
    pub struct Devcontainer {
        pub name: String,
        pub image: String,
    }

    pub fn parse_devcontainer(filename: &str) -> Devcontainer {
        let mut file = File::open(filename).expect("file not found");
        let mut contents = String::new();
        file.read_to_string(&mut contents).expect("something went wrong reading the file");

        /* we need to get rid of comments in the json */
        let re = regex::Regex::new(r"//.*\r?\n").unwrap();
        let result = re.replace_all(&contents, "");

        let json: Value = serde_json::from_str(&result).unwrap();
        let image = json["image"].as_str().unwrap();
        let name = json["name"].as_str().unwrap();

        Devcontainer {
            name: name.to_string(),
            image: image.to_string(),
        }
    }

    // identify devcontainer in the folder structure of the passed workspace folder
    // search in the following order:
    // 1. .devcontainer/devcontainer.json
    // and return the parse_devcontainer result
    pub fn identify_devcontainer(workspace_folder: &str) -> Devcontainer {
        let devcontainer_path = format!("{}/.devcontainer/devcontainer.json", workspace_folder);
        parse_devcontainer(&devcontainer_path)
    }
}

fn main() {
    println!("susi");
}

#[cfg(test)]
mod tests {
    use crate::susi;

    #[test]
    fn parse_simple_devcontainer() {
        let result = susi::parse_devcontainer("test/devcontainer.simple.json");
        assert_eq!(result.name, "Rust");
        assert_eq!(result.image, "mcr.microsoft.com/devcontainers/rust:1-bullseye");
    }

    #[test]
    fn identify_devcontainer() {
        let result_identify = susi::identify_devcontainer("test/workspaces/simple");
        let result_baseline = susi::parse_devcontainer("test/workspaces/simple/.devcontainer/devcontainer.json");

        assert_eq!(result_identify.name, result_baseline.name);
        assert_eq!(result_identify.image, result_baseline.image);
    }
}