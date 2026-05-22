{
  description = "CLI tools monorepo — auto-discovered";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
        root = ./.;
        rootStr = toString root;

        # ------------------------------------------------------------------
        # Auto-discovery
        # ------------------------------------------------------------------
        excludeDirs = [
          ".git"
          ".github"
          "node_modules"
          "result"
        ];

        entries = builtins.readDir root;

        # Directories only, exclude hidden / non-tool dirs
        toolDirs = lib.filterAttrs (
          name: type: type == "directory" && !builtins.elem name excludeDirs && !lib.hasPrefix "." name
        ) entries;

        # Check if a file exists inside a tool dir
        hasFile = dir: file: builtins.pathExists "${rootStr}/${dir}/${file}";

        # Read optional .nix-tool.nix config
        readConfig =
          dir:
          let
            p = "${rootStr}/${dir}/.nix-tool.nix";
          in
          if builtins.pathExists p then import p else { };

        # ------------------------------------------------------------------
        # Bun tool builder
        # ------------------------------------------------------------------
        mkBunTool =
          {
            pname,
            binName ? pname,
            entryPoint ? "index.ts",
            installDeps ? false,
          }:
          pkgs.stdenv.mkDerivation {
            pname = pname;
            version = "0.1.0";
            src = rootStr + "/${pname}";
            buildInputs = [ pkgs.bun ];
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin $out/lib/${pname}
              cp -r . $out/lib/${pname}/
              cd $out/lib/${pname}
              ${lib.optionalString installDeps ''
                bun install --frozen-lockfile 2>/dev/null || true
              ''}
              cat > $out/bin/${binName} <<'WRAPPER'
              #!/bin/sh
              exec ${pkgs.bun}/bin/bun run $out/lib/${pname}/${entryPoint} "$@"
              WRAPPER
              chmod +x $out/bin/${binName}
              runHook postInstall
            '';
          };

        # ------------------------------------------------------------------
        # Node build tool builder (tsc / tsup)
        # ------------------------------------------------------------------
        mkNodeTool =
          {
            pname,
            binName ? pname,
            buildCmd ? "npx tsc",
            npmDepsHash ? pkgs.lib.fakeHash,
          }:
          pkgs.buildNpmPackage {
            pname = pname;
            version = "0.1.0";
            src = rootStr + "/${pname}";
            inherit npmDepsHash;
            nodejs = pkgs.nodejs_22;

            buildPhase = ''
              runHook preBuild
              ${buildCmd}
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/lib/${pname}
              cp -r dist $out/lib/${pname}/dist
              cp package.json $out/lib/${pname}/
              npm prune --omit=dev 2>/dev/null || true
              [ -d node_modules ] && cp -r node_modules $out/lib/${pname}/
              mkdir -p $out/bin
              cat > $out/bin/${binName} <<'WRAPPER'
              #!/bin/sh
              exec node $out/lib/${pname}/dist/index.js "$@"
              WRAPPER
              chmod +x $out/bin/${binName}
              runHook postInstall
            '';
          };

        # ------------------------------------------------------------------
        # Classify & build each tool directory
        # ------------------------------------------------------------------
        buildTool =
          name:
          let
            cfg = readConfig name;

            # If type is explicitly set in .nix-tool.nix, trust it
            toolType =
              cfg.type or (
                if hasFile name "tsconfig.json" then
                  "node"
                else if hasFile name "bun.lock" || hasFile name "bun.lockb" then
                  "bun"
                else if hasFile name "index.ts" then
                  "bun"
                else
                  null
              );

            # Detect entry point for bun tools
            bunEntry = if hasFile name "src/index.ts" then "src/index.ts" else "index.ts";
          in
          if toolType == "bun" then
            mkBunTool {
              pname = cfg.pname or name;
              binName = cfg.binName or name;
              entryPoint = cfg.entryPoint or bunEntry;
              installDeps = hasFile name "bun.lock" || hasFile name "bun.lockb";
            }
          else if toolType == "node" then
            mkNodeTool {
              pname = cfg.pname or name;
              binName = cfg.binName or name;
              buildCmd = cfg.buildCmd or "npx tsc";
              npmDepsHash = cfg.npmDepsHash or pkgs.lib.fakeHash;
            }
          else
            null;

        # Build all tools, filter out nulls (unrecognised dirs)
        toolList = builtins.filter (x: x.value != null) (
          builtins.map (n: {
            name = n;
            value = buildTool n;
          }) (builtins.attrNames toolDirs)
        );

        toolPackages = builtins.listToAttrs toolList;

        # Pick a sensible default: git-taiwa or first alphabetically
        defaultPkg =
          if toolPackages ? git-taiwa then
            toolPackages.git-taiwa
          else if toolList != [ ] then
            (builtins.head toolList).value
          else
            null;

      in
      {
        packages = toolPackages // {
          default = defaultPkg;
        };

        devShells.default = pkgs.mkShell {
          name = "cli-tools-dev";
          packages = with pkgs; [
            nodejs_22
            nodePackages.typescript
            nodePackages.pnpm
            bun
            claude-code
            opencode
          ];
          shellHook = ''
            echo "CLI Tools Dev Shell (auto-discovered)"
            echo "Node: $(node --version)  Bun: $(bun --version)"
            echo ""
            echo "Available packages:"
            ${builtins.concatStringsSep "\n" (
              builtins.map (n: "echo \"  nix run .#${n}\"") (builtins.attrNames toolPackages)
            )}
          '';
        };
      }
    );
}
