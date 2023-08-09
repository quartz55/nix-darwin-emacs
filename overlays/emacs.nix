self: super:
let
  mkEmacs = namePrefix: repoMetaFile: { ... }@args:
    let
      repoMeta = super.lib.importJSON repoMetaFile;
      fetcher =
        if repoMeta.type == "savannah" then
          super.fetchFromSavannah
        else
          throw "Unknown repo type ${repoMeta.type}";
    in
    builtins.foldl'
      (drv: fn: fn drv)
      super.emacs
      [
        (drv: drv.override ({ srcRepo = true; } // args))

        (drv: drv.overrideAttrs (
          old: {
            name = "${namePrefix}-${repoMeta.version}";
            inherit (repoMeta) version;
            src = fetcher (builtins.removeAttrs repoMeta [ "type" "version" ]);

            patches = [ ];

            postPatch = old.postPatch + ''
              substituteInPlace lisp/loadup.el \
              --replace '(emacs-repository-get-version)' '"${repoMeta.rev}"' \
              --replace '(emacs-repository-get-branch)' '"master"'
            '';
          }
        ))

        # fix native compiler error
        (drv: drv.overrideAttrs (
          old: {
            postPatch = old.postPatch + (super.lib.optionalString ((old ? NATIVE_FULL_AOT) || (old ? env.NATIVE_FULL_AOT))
              (
                let
                  backendPath = (super.lib.concatStringsSep " "
                    (builtins.map (x: ''\"-B${x}\"'') ([
                      # Paths necessary so the JIT compiler finds its libraries:
                      "${super.lib.getLib self.libgccjit}/lib"
                      "${super.lib.getLib self.libgccjit}/lib/gcc"
                      "${super.lib.getLib self.stdenv.cc.libc}/lib"
                    ] ++ super.lib.optionals (self.stdenv.cc?cc.libgcc) [
                      "${super.lib.getLib self.stdenv.cc.cc.libgcc}/lib"
                    ] ++ [

                      # Executable paths necessary for compilation (ld, as):
                      "${super.lib.getBin self.stdenv.cc.cc}/bin"
                      "${super.lib.getBin self.stdenv.cc.bintools}/bin"
                      "${super.lib.getBin self.stdenv.cc.bintools.bintools}/bin"
                    ])));
                in
                ''
                  substituteInPlace lisp/emacs-lisp/comp.el --replace \
                    "(defcustom comp-libgccjit-reproducer nil" \
                    "(setq native-comp-driver-options '(${backendPath}))
                     (defcustom comp-libgccjit-reproducer nil"
                ''
              ));
          }
        ))

        # link tree-sitter dependencies
        (drv: drv.overrideAttrs (
          old:
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
            patches = old.patches ++
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
            buildInputs = old.buildInputs ++ [ tree-sitter-grammars ];
            buildFlags = "LDFLAGS=-Wl,-rpath,${super.lib.makeLibraryPath [tree-sitter-grammars]}";

            postInstall = old.postInstall + ''
              cp ${./icons/memeplex-wide.icns} $out/Applications/Emacs.app/Contents/Resources/Emacs.icns
            '';
          }
        ))

        # make emacs package available on macOS only
        (drv: drv.overrideAttrs (
          old: {
            meta = old.meta // {
              platforms = super.lib.platforms.darwin;
            };
          }
        ))

        # reconnect pkgs to the built emacs
        (drv:
          let
            result = drv.overrideAttrs (old: {
              passthru = old.passthru // {
                pkgs = self.emacsPackagesFor result;
              };
            });
          in
          result
        )
      ];
in
{
  emacs-unstable = super.lib.makeOverridable (mkEmacs "emacs-unstable" ../repos/emacs/unstable.json) {
    withSQLite3 = true;
    withTreeSitter = true;
    withWebP = true;
  };

  emacs-29 = super.lib.makeOverridable (mkEmacs "emacs-29" ../repos/emacs/29.json) {
    withSQLite3 = true;
    withTreeSitter = true;
    withWebP = true;
  };

  emacsWithPackagesFromUsePackage = import ../elisp.nix { pkgs = self; };

  emacsWithPackagesFromPackageRequires = import ../packreq.nix { pkgs = self; };
}
