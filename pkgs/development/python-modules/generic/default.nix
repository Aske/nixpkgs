/* This function provides a generic Python package builder.  It is
   intended to work with packages that use `distutils/setuptools'
   (http://pypi.python.org/pypi/setuptools/), which represents a large
   number of Python packages nowadays.  */

{ python, setuptools, unzip, wrapPython, lib, bootstrapped-pip
, ensureNewerSourcesHook }:

{ name

# by default prefix `name` e.g. "python3.3-${name}"
, namePrefix ? python.libPrefix + "-"

, buildInputs ? []

# propagate build dependencies so in case we have A -> B -> C,
# C can import package A propagated by B 
, propagatedBuildInputs ? []

# passed to "python setup.py build_ext"
# https://github.com/pypa/pip/issues/881
, setupPyBuildFlags ? []

# DEPRECATED: use propagatedBuildInputs
, pythonPath ? []

# used to disable derivation, useful for specific python versions
, disabled ? false

, meta ? {}

# Execute before shell hook
, preShellHook ? ""

# Execute after shell hook
, postShellHook ? ""

# Additional arguments to pass to the makeWrapper function, which wraps
# generated binaries.
, makeWrapperArgs ? []

# Additional flags to pass to "pip install".
, installFlags ? []

# Raise an error if two packages are installed with the same name
, catchConflicts ? true

, format ? "setup"

, ... } @ attrs:


# Keep extra attributes from `attrs`, e.g., `patchPhase', etc.
if disabled
then throw "${name} not supported for interpreter ${python.executable}"
else

let
  # use setuptools shim (so that setuptools is imported before distutils)
  # pip does the same thing: https://github.com/pypa/pip/pull/3265
  setuppy = ./run_setup.py;

  formatspecific =
    if format == "wheel" then
      {
        unpackPhase = ''
          mkdir dist
          cp $src dist/"''${src#*-}"
        '';

        # Wheels are pre-compiled
        buildPhase = attrs.buildPhase or ":";
        installCheckPhase = attrs.checkPhase or ":";

        # Wheels don't have any checks to run
        doInstallCheck = attrs.doCheck or false;
      }
    else if format == "setup" then
      {
        # propagate python/setuptools to active setup-hook in nix-shell
        propagatedBuildInputs =
          propagatedBuildInputs ++ [ python setuptools ];

        # we copy nix_run_setup.py over so it's executed relative to the root of the source
        # many project make that assumption
        buildPhase = attrs.buildPhase or ''
          runHook preBuild
          cp ${setuppy} nix_run_setup.py
          ${python.interpreter} nix_run_setup.py ${lib.optionalString (setupPyBuildFlags != []) ("build_ext " + (lib.concatStringsSep " " setupPyBuildFlags))} bdist_wheel
          runHook postBuild
        '';

        installCheckPhase = attrs.checkPhase or ''
          runHook preCheck
          ${python.interpreter} nix_run_setup.py test
          runHook postCheck
        '';

        # Python packages that are installed with setuptools
        # are typically distributed with tests.
        # With Python it's a common idiom to run the tests
        # after the software has been installed.

        # For backwards compatibility, let's use an alias
        doInstallCheck = attrs.doCheck or true;
      }
    else
      throw "Unsupported format ${format}";
in
python.stdenv.mkDerivation (builtins.removeAttrs attrs ["disabled" "doCheck"] // {
  name = namePrefix + name;

  buildInputs = [ wrapPython bootstrapped-pip ] ++ buildInputs ++ pythonPath
    ++ [ (ensureNewerSourcesHook { year = "1980"; }) ]
    ++ (lib.optional (lib.hasSuffix "zip" attrs.src.name or "") unzip);

  pythonPath = pythonPath;

  configurePhase = attrs.configurePhase or ''
    runHook preConfigure

    # patch python interpreter to write null timestamps when compiling python files
    # this way python doesn't try to update them when we freeze timestamps in nix store
    export DETERMINISTIC_BUILD=1

    runHook postConfigure
  '';

  # Python packages don't have a checkPhase, only an installCheckPhase
  doCheck = false;

  installPhase = attrs.installPhase or ''
    runHook preInstall

    mkdir -p "$out/${python.sitePackages}"
    export PYTHONPATH="$out/${python.sitePackages}:$PYTHONPATH"

    pushd dist
    ${bootstrapped-pip}/bin/pip install *.whl --no-index --prefix=$out --no-cache ${toString installFlags}
    popd

    runHook postInstall
  '';

  postFixup = attrs.postFixup or ''
    wrapPythonPrograms
  '' + lib.optionalString catchConflicts ''
    # check if we have two packages with the same name in closure and fail
    # this shouldn't happen, something went wrong with dependencies specs
    ${python.interpreter} ${./catch_conflicts.py}
  '';

  shellHook = attrs.shellHook or ''
    ${preShellHook}
    if test -e setup.py; then
       tmp_path=$(mktemp -d)
       export PATH="$tmp_path/bin:$PATH"
       export PYTHONPATH="$tmp_path/${python.sitePackages}:$PYTHONPATH"
       mkdir -p $tmp_path/${python.sitePackages}
       ${bootstrapped-pip}/bin/pip install -e . --prefix $tmp_path
    fi
    ${postShellHook}
  '';

  meta = with lib.maintainers; {
    # default to python's platforms
    platforms = python.meta.platforms;
  } // meta // {
    # add extra maintainer(s) to every package
    maintainers = (meta.maintainers or []) ++ [ chaoflow domenkozar ];
    # a marker for release utilities to discover python packages
    isBuildPythonPackage = python.meta.platforms;
  };
} // formatspecific)
