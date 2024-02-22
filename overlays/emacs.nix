self: super:
let
  mkEmacs = namePrefix: repoMetaFile: patches: { ... }@args:
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
            src = fetcher (builtins.removeAttrs repoMeta [ "type" "version" "branch" ]);

            patches = [ ];

            postPatch = old.postPatch + ''
              substituteInPlace lisp/loadup.el \
              --replace-warn '(emacs-repository-get-version)' '"${repoMeta.rev}"' \
              --replace-warn '(emacs-repository-get-branch)' '"${repoMeta.branch}"'
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
                  substituteInPlace lisp/emacs-lisp/comp.el --replace-warn \
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
              echo "patching ./parser with id $out/lib/${lib drv}"
              cp ${drv}/parser .
              chmod +w ./parser
              install_name_tool -id $out/lib/${lib drv} ./parser
              cp ./parser $out/lib/${lib drv}
              ${self.pkgs.darwin.sigtool}/bin/codesign -s - -f $out/lib/${lib drv}
            '';

            allGrammars = map
              (grammar:
                grammar.overrideAttrs (prev: {
                  env = (prev.env or { }) // {
                    # Ensure enough space was given, which is useful when updating the id of shared lib.
                    #
                    # Or, an error might be raised:
                    #
                    #   error: install_name_tool: changing install names or rpaths can't be redone for: ./parser
                    #   (for architecture x86_64) because larger updated load commands do not fit (the program
                    #   must be relinked, and you may need to use -headerpad or -headerpad_max_install_names)
                    #
                    NIX_LDFLAGS = "-headerpad_max_install_names";
                  };
                }))
              super.pkgs.tree-sitter.allGrammars;
            tree-sitter-grammars = super.runCommandCC "tree-sitter-grammars" { }
              (super.lib.concatStringsSep "\n" ([ "mkdir -p $out/lib" ] ++ (map linkCmd allGrammars)));
          in
          {
            patches = old.patches ++ patches;
            buildInputs = old.buildInputs ++ [ tree-sitter-grammars ];
            buildFlags = "LDFLAGS=-Wl,-rpath,${super.lib.makeLibraryPath [tree-sitter-grammars]}";

            postInstall = old.postInstall + ''
              cp ${./icons/Emacs.icns} $out/Applications/Emacs.app/Contents/Resources/Emacs.icns
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
  emacs-unstable = super.lib.makeOverridable
    (mkEmacs "emacs-unstable" ../repos/emacs/unstable.json [
      # patches from https://github.com/d12frosted/homebrew-emacs-plus
      ./patches-30/fix-window-role.patch
      ./patches-30/poll.patch
      ./patches-30/system-appearance.patch
      ./patches-30/round-undecorated-frame.patch
    ])
    {
      withSQLite3 = true;
      withTreeSitter = true;
      withWebP = true;
    };

  emacs-29 = super.lib.makeOverridable
    (mkEmacs "emacs-29" ../repos/emacs/29.json [
      # patches from https://github.com/d12frosted/homebrew-emacs-plus
      ./patches-29/fix-window-role.patch
      ./patches-29/poll.patch
      ./patches-29/system-appearance.patch
      ./patches-29/round-undecorated-frame.patch
    ])
    {
      withSQLite3 = true;
      withTreeSitter = true;
      withWebP = true;
    };

  emacsWithPackagesFromUsePackage = import ../elisp.nix { pkgs = self; };

  emacsWithPackagesFromPackageRequires = import ../packreq.nix { pkgs = self; };
}
