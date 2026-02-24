{
  lib,
  pkgs,
  stdenv,
  callPackages,
  fetchFromGitHub,
  postgresql,
  rust-bin,
  latestOnly ? false,
}:
let
  pname = "pg_tokenizer";
  allVersions = (builtins.fromJSON (builtins.readFile ../versions.json)).${pname};
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  versionsToUse =
    if latestOnly then
      { "${latestVersion}" = supportedVersions.${latestVersion}; }
    else
      supportedVersions;
  versionsBuilt = if latestOnly then [ latestVersion ] else versions;
  numberOfVersionsBuilt = builtins.length versionsBuilt;
  build =
    version: value:
    let
      cargo = rust-bin.stable.${value.rust}.default;
      mkPgrxExtension = callPackages ../../cargo-pgrx/mkPgrxExtension.nix {
        rustVersion = value.rust;
        pgrxVersion = value.pgrx;
      };
      src = fetchFromGitHub {
        owner = "tensorchord";
        repo = "pg_tokenizer.rs";
        rev = "refs/tags/${version}";
        hash = value.hash;
      };
      lockFile =
        if builtins.pathExists "${src}/Cargo.lock" then
          "${src}/Cargo.lock"
        else
          ./Cargo-${version}.lock;
    in
    mkPgrxExtension rec {
      inherit
        pname
        version
        postgresql
        src
        ;

      nativeBuildInputs = [ cargo ];
      buildInputs = [ postgresql ];
      CARGO = "${cargo}/bin/cargo";
      doCheck = false;
      cargoLock = {
        inherit lockFile;
        allowBuiltinFetchGit = true;
      };
      # buildRustPackage's vendor step reads ./Cargo.lock from source root.
      postPatch = lib.optionalString (!builtins.pathExists "${src}/Cargo.lock") ''
        ln -sf ${lockFile} Cargo.lock
      '';
      buildFeatures = [
        "pg${lib.versions.major postgresql.version}"
        "lindera-ipadic"
      ];

      env = lib.optionalAttrs stdenv.isDarwin {
        POSTGRES_LIB = "${postgresql}/lib";
        RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
      };

      postInstall = ''
        mv $out/lib/${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          $out/share/postgresql/extension/${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control
        rm $out/share/postgresql/extension/${pname}.control

        if [[ "${version}" == "${latestVersion}" ]]; then
          {
            echo "default_version = '${latestVersion}'"
            cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
          } > $out/share/postgresql/extension/${pname}.control
          ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
        fi
      '';

      meta = with lib; {
        description = "PostgreSQL tokenizer extension";
        homepage = "https://github.com/tensorchord/pg_tokenizer.rs";
        license = licenses.agpl3Only;
        inherit (postgresql.meta) platforms;
      };
    };
  packages = builtins.attrValues (lib.mapAttrs build versionsToUse);
in
(pkgs.buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];

  postBuild = ''
    (set -x
       test "$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)" = "${
         toString (numberOfVersionsBuilt + 1)
       }"
    )
  '';

  passthru = {
    versions = versionsBuilt;
    numberOfVersions = numberOfVersionsBuilt;
    inherit pname latestOnly;
    defaultSettings = {
      shared_preload_libraries = [ "pg_tokenizer" ];
    };
    version =
      if latestOnly then
        latestVersion
      else
        "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}).overrideAttrs
  (_: {
    requiredSystemFeatures = [ "big-parallel" ];
  })
