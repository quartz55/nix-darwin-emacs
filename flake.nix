{
  description = "A nix overlay for bleeding edge Emacs on macOS.";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs =
    { self
    , nixpkgs
    , flake-utils
    }: {
      # self: super: must be named final: prev: for `nix flake check` to be happy
      overlays = {
        default = final: prev: import ./overlays/emacs.nix final prev;
        emacs = final: prev: import ./overlays/emacs.nix final prev;
      };
    } // flake-utils.lib.eachDefaultSystem (system: (
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
        inherit (pkgs) lib;
        overlayAttrs = builtins.attrNames (import ./. pkgs pkgs);
      in
      {
        packages =
          let
            drvAttrs = builtins.filter (n: lib.isDerivation pkgs.${n}) overlayAttrs;
          in
          lib.listToAttrs (map (n: lib.nameValuePair n pkgs.${n}) drvAttrs);
      }
    ));

}
