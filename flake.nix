/*

#INPUT

I am looking at deploying k3s on Mac and Fedora Silverblue based workstations. Following are objectives we want to achieve:

- Install Podman VM on MacOS - Silicon M4
- Install Deterministic Nix on MacOS
- Flake.Nix that would setup k3s on Podman VM for MacOS and as Native Container on Fedora SilverBlue
- Install kubectl, k9s, helm, headlamp on MacOS and Fedora SilverBlue
- Install VSCode with ContainerTools extension
- Use Titl for local automated deployment 
- use Containerd runtime
- Use Harbor.nbt.local as caching proxy for container images
- Use nixpkgs version 25.05
- Use latest k3s version
- Add operation status logs in nixfiles to notify user of the operation, add emoticons to make it better

Note:
- Don't consider LIMA
- Don't consider Docker / Docker Daemon / Docker Engine / Docker CLI

#INPUT END

Given the above inputs generate flake.nix supporting both x86_64 and arm64 architechtures
Todays date is July 2, 2025. so use packages, references, and code syntax valid on today's date
Nix version is 2.29, so validate nix files against that
add steps for installing k3s, podman VM on mac os, and checks for existing k3s / podman vm

*/
{
  description = "Dev environment using Nix flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    nixunstable.url = "github:NixOS/nixpkgs/nixos-unstable";

  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nixunstable,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };
        unstablepkgs = import nixunstable {
          inherit system;
        };

        # Define your extensions here
        myExtensions = with pkgs.vscode-extensions; [
          ms-vscode-remote.vscode-remote-extensionpack
          esbenp.prettier-vscode
          sonarsource.sonarlint-vscode
          ms-dotnettools.csdevkit
        ];

        vscode-with-extensions = pkgs.vscode-with-extensions.override {
          vscodeExtensions = myExtensions;
        };

        # Podman VM setup for MacOS
        podmanVMExists = builtins.tryEval (
          pkgs.runCommand "check-podman-vm" {
            shell = ''
              if podman machine ls | grep -q "podman-vm"; then
                echo "Podman VM exists ✅"
                exit 0
              else
                echo "Podman VM does not exist ❌"
                exit 1
              fi
            '';
          }
        );

        podmanVM = pkgs.virtualisation.podman.createVM {
          name = "podman-vm";
          memory = "4GB";
          cpuCount = 2;
          image = pkgs.virtualisation.podman.vmImage;
        };

        # k3s installation setup
        k3sExists = builtins.tryEval (
          pkgs.runCommand "check-k3s" {
            shell = ''
              if [ -x "$(command -v k3s)" ]; then
                echo "K3s already installed ✅"
                exit 0
              else
                echo "K3s not found ❌"
                exit 1
              fi
            '';
          }
        );

        k3sSetup = pkgs.runCommand "install-k3s" {
          buildInputs = [ pkgs.curl ];

          shell = ''
            echo "Installing K3s in Podman VM 🖥️" > $out/status.log
            curl -sfL https://get.k3s.io | sh -
            echo "K3s installation complete ✅" >> $out/status.log
          '';
        };
        statusMessage = "MacOS setup in progress 🍏";

      in
      {
        nixpkgs.config.allowUnfree = true;
        devShells.default = pkgs.mkShell {

          buildInputs = [
            unstablepkgs.nixfmt-rfc-style
            # pkgs.tilt
            pkgs.kubectl
            # pkgs.helm # Not available for MacOS
            # pkgs.nerdctl # Note nerdctl is available only for linux
            pkgs.yq
            pkgs.jq
            pkgs.direnv
            # pkgs.minikube
            pkgs.k9s
            # pkgs.colima # We install binary from Nix, still requires manual start

            # pkgs.ctlptl # CLI for declaratively setting up local Kubernetes clusters
            # pkgs.kind # kind has issues when restarting the system
            pkgs.git
            pkgs.krew


          ];


        };
      }
    );
}
