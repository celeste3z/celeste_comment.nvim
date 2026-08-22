{
  description = "Batteries-included commenting plugin — line/block comment, textobjects, real sticky cursor, and more!";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        mkPlugin = pkgs:
          pkgs.vimUtils.buildVimPlugin {
            pname = "celeste_comment.nvim";
            version = "latest";
            src = ./.;
          };
      in {
        packages.default = mkPlugin pkgs;

        overlays.default = _final: _prev: {
          vimPlugins =
            (_prev.vimPlugins or {})
            // {
              celeste-comment-nvim = mkPlugin _final;
            };
        };
      }
    );
}
