{
  description = "An interactive NixOS GitOps Bootstrapper";

  inputs = {
    # We only need nixpkgs to provide the basic shell environment for the script.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    # This flake's only job is to provide a runnable "app" that is our script.
    # This allows a user to run it with a single 'nix run' command.
    apps.x86_64-linux.default = {
      type = "app";
      program = ./bootstrap.sh;
    };
  };
}
