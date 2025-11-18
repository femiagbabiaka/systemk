{
  description = "Systemk: virtual kubelet for systemd";

  # Flake inputs
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs (use 0.1 for unstable)

  # Flake outputs
  outputs =
    { self, ... }@inputs:
    let
      # The systems supported for this flake's outputs
      supportedSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
      ];

      # Helper for providing system-specific attributes
      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            # Provides a system-specific, configured Nixpkgs
            pkgs = import inputs.nixpkgs {
              inherit system;
              # Enable using unfree packages
              config.allowUnfree = true;
            };
          }
        );
    in
    {
      # Package outputs by this flake
      packages = forEachSupportedSystem (
        { pkgs, system }:
        let
          systemkPackage = pkgs.buildGoModule {
            pname = "systemk";
            version = "0.0.1-${self.shortRev or "dirty"}";

            src = ./.;

            # Update this hash after first build attempt when it fails
            # The build will tell you the correct hash
            vendorHash = "sha256-LH7BMxxMv014dvtPdv1lLQ+wCc8fhBTZ6CGP0wUtCI4=";

            # CGO is required for systemd bindings
            # On Linux, we need systemd development libraries
            nativeBuildInputs = with pkgs; [ pkg-config ];

            buildInputs = with pkgs; [ systemd.dev ];

            # Build tags and flags
            tags = [ "cgo" ];

            # Set build-time variables
            ldflags = [
              "-s"
              "-w"
              "-X main.buildVersion=${self.rev or "dev"}"
              "-X main.buildTime=1970-01-01T00:00:00Z"
            ];

            # Skip tests that require systemd to be running
            doCheck = false;

            meta = with pkgs.lib; {
              description = "Virtual kubelet provider that uses systemd as its backend";
              homepage = "https://github.com/virtual-kubelet/systemk";
              license = licenses.asl20;
              maintainers = [ ];
              # Only works on Linux systems with systemd
              platforms = platforms.linux;
            };
          };
        in
          {
            systemk = systemkPackage;
            default = systemkPackage;
          }
      );

      # Development environments output by this flake

      # To activate the default environment:
      # nix develop
      # Or if you use direnv:
      # direnv allow
      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          # Run `nix develop` to activate this environment or `direnv allow` if you have direnv installed
          default = pkgs.mkShell {
            # The Nix packages provided in the environment
            packages =
              with pkgs;
              [
                # Add the flake's formatter to your project's environment
                self.formatter.${system}

                # Go development tools
                go
                gopls
                gotools
                go-tools

                # Build dependencies
                pkg-config
              ]
              ++ (if stdenv.isLinux then [ systemd.dev ] else [ ]);

            # Set any environment variables for your development environment
            env = { };

            # Add any shell logic you want executed when the environment is activated
            shellHook = ''
              echo "Systemk development environment"
              echo "Go version: $(go version)"
              ${
                if pkgs.stdenv.isLinux then
                  ''echo "Systemd available for CGO builds"''
                else
                  ''echo "Warning: systemd not available on macOS - systemk requires Linux to build"''
              }
            '';
          };
        }
      );

      # Nix formatter

      # This applies the formatter that follows RFC 166, which defines a standard format:
      # https://github.com/NixOS/rfcs/pull/166

      # To format all Nix files:
      # git ls-files -z '*.nix' | xargs -0 -r nix fmt
      # To check formatting:
      # git ls-files -z '*.nix' | xargs -0 -r nix develop --command nixfmt --check
      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt-rfc-style);
    };
}
