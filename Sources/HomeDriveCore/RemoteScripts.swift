import Foundation

/// The fixed shell scripts run on the Linux PC. User data only ever reaches them as `$1`, `$2`, ...
/// They stick to POSIX `sh` plus standard tools (find, tar, mv, rm, df, du) so nothing has to be
/// installed on the PC.
public enum RemoteScripts {
    /// Prints `key \t value` lines describing the remote machine.
    public static let probe = #"""
    printf 'home\t%s\n' "$HOME"
    printf 'host\t%s\n' "$(hostname 2>/dev/null || uname -n)"
    printf 'os\t%s\n' "$(uname -sr)"
    command -v gio >/dev/null 2>&1 && printf 'trash\t1\n'
    found=0
    if command -v xdg-user-dir >/dev/null 2>&1; then
      for k in DESKTOP DOCUMENTS DOWNLOAD PICTURES MUSIC VIDEOS; do
        p=$(xdg-user-dir "$k" 2>/dev/null)
        if [ -n "$p" ] && [ "$p" != "$HOME" ] && [ -d "$p" ]; then
          printf 'place\t%s\n' "$p"; found=1
        fi
      done
    fi
    if [ "$found" = 0 ]; then
      for d in Desktop Documents Downloads Pictures Music Videos; do
        [ -d "$HOME/$d" ] && printf 'place\t%s\n' "$HOME/$d"
      done
    fi
    df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {printf "disk\t%s\t%s\n", $2, $4}'
    exit 0
    """#

    /// Lists the folder `$1` (see `ListingParser` for the format).
    public static let list = #"""
    d=$1
    [ -d "$d" ] || { printf 'No such folder: %s\n' "$d" >&2; exit 3; }
    [ -r "$d" ] && [ -x "$d" ] || { printf 'Permission denied: %s\n' "$d" >&2; exit 4; }
    if find "$d" -maxdepth 0 -printf '' >/dev/null 2>&1; then
      find "$d" -mindepth 1 -maxdepth 1 -printf '%y%Y\t%s\t%T@\t%m\t%f\0' 2>/dev/null
    else
      find "$d" -mindepth 1 -maxdepth 1 -exec stat -f '%HT%t%z%t%m%t%Lp%t%N' {} + 2>/dev/null | tr '\n' '\000'
    fi
    exit 0
    """#

    /// Creates folder `$1` (parent must exist).
    public static let makeDirectory = #"""
    [ -e "$1" ] && { printf '"%s" already exists\n' "${1##*/}" >&2; exit 17; }
    mkdir -- "$1"
    """#

    /// Renames `$1` to `$2`, refusing to overwrite.
    public static let rename = #"""
    [ -e "$2" ] && { printf '"%s" already exists\n' "${2##*/}" >&2; exit 17; }
    mv -- "$1" "$2"
    """#

    /// Moves every argument to the desktop trash with `gio trash`.
    public static let trash = #"""
    gio trash -- "$@"
    """#

    /// Permanently deletes every argument.
    public static let delete = #"""
    rm -rf -- "$@"
    """#

    /// Prints, NUL-separated, which of the names `$2...` already exist inside folder `$1`.
    public static let existing = #"""
    d=$1; shift
    for n in "$@"; do
      if [ -e "$d/$n" ] || [ -L "$d/$n" ]; then printf '%s\0' "$n"; fi
    done
    exit 0
    """#

    /// Prints the total size in KiB of all arguments.
    public static let diskUsage = #"""
    du -sk -- "$@" 2>/dev/null | awk '{s += $1} END {printf "%d\n", s}'
    """#

    /// Writes a tar stream of `$1/$2` to stdout (used for downloads).
    public static let tarCreate = #"""
    cd -- "$1" || exit 1
    exec tar -cf - "./$2"
    """#

    /// Reads a tar stream from stdin and places its single item `$2` into folder `$1`.
    /// Extracts into a hidden staging folder first, so a cancelled or failed upload
    /// never leaves a half-written file under the real name. `$3` = 1 allows replacing.
    public static let tarExtract = #"""
    dest=$1; name=$2; replace=$3
    mkdir -p -- "$dest" || exit 1
    stage=$(mktemp -d "$dest/.homedrive-partial.XXXXXX") || exit 1
    if tar -xf - -C "$stage"; then
      if [ -e "$dest/$name" ] || [ -L "$dest/$name" ]; then
        if [ "$replace" = 1 ]; then
          rm -rf -- "$dest/$name"
        else
          rm -rf -- "$stage"; printf '"%s" already exists\n' "$name" >&2; exit 17
        fi
      fi
      mv -- "$stage/$name" "$dest/$name" && rmdir -- "$stage"
    else
      status=$?
      rm -rf -- "$stage"
      exit "$status"
    fi
    """#
}
