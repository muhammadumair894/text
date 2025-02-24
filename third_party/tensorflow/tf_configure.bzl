"""Setup TensorFlow as external dependency.

This is used for the generation of the dynamic libraries used for custom ops.
See: http://github.com/tensorflow/custom-op
"""

_TF_HEADER_DIR = "TF_HEADER_DIR"
_TF_SHARED_LIBRARY_DIR = "TF_SHARED_LIBRARY_DIR"

def _tpl(repository_ctx, tpl, substitutions = {}, out = None):
    if not out:
        out = tpl
    repository_ctx.template(
        out,
        Label("//third_party/tensorflow:%s.tpl" % tpl),
        substitutions,
    )

def _fail(msg):
    """Output failure message when auto configuration fails."""
    red = "\033[0;31m"
    no_color = "\033[0m"
    fail("%sPython Configuration Error:%s %s\n" % (red, no_color, msg))

def _is_windows(repository_ctx):
    """Returns true if the host operating system is windows."""
    os_name = repository_ctx.os.name.lower()
    if os_name.find("windows") != -1:
        return True
    return False

def _execute(
        repository_ctx,
        cmdline,
        error_msg = None,
        error_details = None,
        empty_stdout_fine = False):
    """Executes an arbitrary shell command.

    Helper for executes an arbitrary shell command.

    Args:
      repository_ctx: the repository_ctx object.
      cmdline: list of strings, the command to execute.
      error_msg: string, a summary of the error if the command fails.
      error_details: string, details about the error or steps to fix it.
      empty_stdout_fine: bool, if True, an empty stdout result is fine, otherwise
        it's an error.

    Returns:
      The result of repository_ctx.execute(cmdline).
    """
    result = repository_ctx.execute(cmdline)
    if result.stderr or not (empty_stdout_fine or result.stdout):
        _fail("\n".join([
            error_msg.strip() if error_msg else "Repository command failed",
            result.stderr.strip(),
            error_details if error_details else "",
        ]))
    return result

def _read_dir(repository_ctx, src_dir):
    """Returns a string with all files in a directory.

    Finds all files inside a directory, traversing subfolders and following
    symlinks. The returned string contains the full path of all files
    separated by line breaks.

    Args:
        repository_ctx: the repository_ctx object.
        src_dir: directory to find files from.

    Returns:
        A string of all files inside the given dir.
    """
    if _is_windows(repository_ctx):
        src_dir = src_dir.replace("/", "\\")
        find_result = _execute(
            repository_ctx,
            ["cmd.exe", "/c", "dir", src_dir, "/b", "/s", "/a-d"],
            empty_stdout_fine = True,
        )

        # src_files will be used in genrule.outs where the paths must
        # use forward slashes.
        result = find_result.stdout.replace("\\", "/")
    else:
        find_result = _execute(
            repository_ctx,
            ["find", src_dir, "-follow", "-type", "f"],
            empty_stdout_fine = True,
        )
        result = find_result.stdout
    return result

def _genrule(genrule_name, command, outs):
    """Returns a string with a genrule.

    Genrule executes the given command and produces the given outputs.

    Args:
        genrule_name: A unique name for genrule target.
        command: The command to run.
        outs: A list of files generated by this rule.

    Returns:
        A genrule target.
    """
    return (
        "genrule(\n" +
        '    name = "' +
        genrule_name + '",\n' +
        "    outs = [\n" +
        outs +
        "\n    ],\n" +
        '    cmd = """\n' +
        command +
        '\n   """,\n' +
        ")\n"
    )

def _norm_path(path):
    """Returns a path with '/' and remove the trailing slash."""
    path = path.replace("\\", "/")
    if path[-1] == "/":
        path = path[:-1]
    return path

def _symlink_genrule_for_dir(
        repository_ctx,
        src_dir,
        dest_dir,
        genrule_name,
        src_files = [],
        dest_files = []):
    """Returns a genrule to symlink(or copy if on Windows) a set of files.

    If src_dir is passed, files will be read from the given directory; otherwise
    we assume files are in src_files and dest_files.

    Args:
        repository_ctx: the repository_ctx object.
        src_dir: source directory.
        dest_dir: directory to create symlink in.
        genrule_name: genrule name.
        src_files: list of source files instead of src_dir.
        dest_files: list of corresonding destination files.

    Returns:
        genrule target that creates the symlinks.
    """
    if src_dir != None:
        src_dir = _norm_path(src_dir)
        dest_dir = _norm_path(dest_dir)
        files = "\n".join(sorted(_read_dir(repository_ctx, src_dir).splitlines()))

        # Create a list with the src_dir stripped to use for outputs.
        dest_files = files.replace(src_dir, "").splitlines()
        src_files = files.splitlines()
    command = []
    outs = []
    for i in range(len(dest_files)):
        if dest_files[i] != "":
            # If we have only one file to link we do not want to use the dest_dir, as
            # $(@D) will include the full path to the file.
            dest = "$(@D)/" + dest_dir + dest_files[i] if len(dest_files) != 1 else "$(@D)/" + dest_files[i]

            # Copy the headers to create a sandboxable setup.
            cmd = "cp -f"
            command.append(cmd + ' "%s" "%s"' % (src_files[i], dest))
            outs.append('        "' + dest_dir + dest_files[i] + '",')
    genrule = _genrule(
        genrule_name,
        " && ".join(command),
        "\n".join(outs),
    )
    return genrule

def _tf_pip_impl(repository_ctx):
    tf_header_dir = repository_ctx.os.environ[_TF_HEADER_DIR]
    tf_header_rule = _symlink_genrule_for_dir(
        repository_ctx,
        tf_header_dir,
        "include",
        "tf_header_include",
    )

    tf_shared_library_dir = repository_ctx.os.environ[_TF_SHARED_LIBRARY_DIR]
    tf_shared_library_path = "%s/libtensorflow_framework.so.1" % tf_shared_library_dir
    tf_shared_library_rule = _symlink_genrule_for_dir(
        repository_ctx,
        None,
        "",
        "libtensorflow_framework.so.1",
        [tf_shared_library_path],
        ["libtensorflow_framework.so.1"],
    )

    _tpl(repository_ctx, "BUILD", {
        "%{TF_HEADER_GENRULE}": tf_header_rule,
        "%{TF_SHARED_LIBRARY_GENRULE}": tf_shared_library_rule,
    })

tf_configure = repository_rule(
    implementation = _tf_pip_impl,
    environ = [
        _TF_HEADER_DIR,
        _TF_SHARED_LIBRARY_DIR,
    ],
)
