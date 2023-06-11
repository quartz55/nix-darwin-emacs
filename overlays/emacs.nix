self: super:
{
  emacs-darwin = super.emacs29.overrideAttrs (final: prev:
    let
      libName = drv: super.lib.removeSuffix "-grammar" drv.pname;
      lib = drv: ''lib${libName drv}.dylib'';
      linkCmd = drv: ''
        cp ${drv}/parser .
        chmod +w ./parser
        install_name_tool -id $out/lib/${lib drv} ./parser
        cp ./parser $out/lib/${lib drv}
        ${self.pkgs.darwin.sigtool}/bin/codesign -s - -f $out/lib/${lib drv}
      '';

      allGrammars = super.pkgs.tree-sitter.allGrammars;
      tree-sitter-grammars = super.runCommandCC "tree-sitter-grammars" { }
        (super.lib.concatStringsSep "\n" ([ "mkdir -p $out/lib" ] ++ (map linkCmd allGrammars)));

    in
    {
      patches = prev.patches ++
        # patches from https://github.com/d12frosted/homebrew-emacs-plus/tree/master/patches
        [
          # fix role of window
          # GNU Emacs's main role is an AXTextField instead of AXWindow, it has to be fixed manually.
          ./patches/fix-window-role.patch

          # better appearance
          ./patches/system-appearance.patch
          ./patches/round-undecorated-frame.patch

          # misc
          ./patches/poll.patch
        ];

      buildInputs = prev.buildInputs ++ [ tree-sitter-grammars ];
      buildFlags = "LDFLAGS=-Wl,-rpath,${super.lib.makeLibraryPath [tree-sitter-grammars]}";

      postInstall = prev.postInstall + ''
        cp ${./icons/memeplex-wide.icns} $out/Applications/Emacs.app/Contents/Resources/Emacs.icns
      '';

    });

  emacsWithPackagesFromUsePackage = import ../elisp.nix { pkgs = self; };

  emacsWithPackagesFromPackageRequires = import ../packreq.nix { pkgs = self; };
}
