#!/usr/bin/env bash

shopt -s extglob
PS4="+ \${BASH_SOURCE##\${rvm_path:-}} : \${FUNCNAME[0]:+\${FUNCNAME[0]}()}  \${LINENO} > "
export PS4
set -o errtrace
set -o errexit

log()  { printf "$*\n" ; return $? ;  }

fail() { log "\nERROR: $*\n" ; exit 1 ; }

usage()
{
  printf "

Usage

  rvm-installer [options] [action]

Options

  --branch <name>               - Install RVM head, from named branch
  --version <head|latest|x.y.z> - Install RVM version [head|latest|x.y.z]
  --trace                       - used to debug the installer script

Actions

  help - Display CLI help (this output)

"
}

fetch_version()
{
  version=$(curl -s -B "${rvm_releases_url}/latest-version.txt" 2>/dev/null)
}

fetch_md5()
{
  md5=$(curl -s -B "${rvm_releases_url}/rvm-${version}.tar.gz.md5" 2>/dev/null)
}

md5_match()
{
  local archive="$1"

  case "$(uname)" in
    Darwin|FreeBSD)
      archive_md5="$(/sbin/md5 -q "${archive}")"
      ;;

    OpenBSD)
      archive_md5="$(/bin/md5 -q "${archive}")"
      ;;

    Linux|*)
      archive_md5="$(md5sum "${archive}")"
      archive_md5="${archive_md5%% *}"
      ;;
  esac

  if [[ "$archive_md5" == "$md5" ]]
  then
    return 0
  else
    return 1
  fi
}

install_release()
{
  local archive url

  archive="${rvm_archives_path}/rvm-${version}.tar.gz"
  url="${rvm_releases_url}/rvm-${version}.tar.gz"

  fetch_md5

  if [[ -s "${archive}" && -n "${md5}" ]] && ! md5_match "${archive}"
  then
    # Remove old installs, if they exist and have incorrect md5.
    if [[ -f "${archive}" ]]
    then
      rm -f "${archive}"
    fi
  fi

  if curl -L "${url}" -o "${archive}"
  then
    true
  else
    fail "Failed to download ${url} to ${archive} using 'curl', error code ($?)"
  fi

  if ! md5_match "$archive"
  then
    fail "ERROR:

Archive package downloaded does not match its calculated md5 checksum ${md5}:

  $rvm_archives_path/rvm-${version}.tar.gz

Retry the installation and/or check your networking setup.

Halting installation.
"
  fi

  if tar zxf "${archive}" -C "$rvm_src_path/" --no-same-owner
  then
    cd "$rvm_src_path/rvm-${version}"
  else
    fail "Failed to extract ${archive} to ${rvm_src_path}/,"\
      "tar command returned error code $?"
  fi
}

install_head()
{
  local remote="origin"

  if [[ -d "${rvm_src_path}/rvm/.git" ]]
  then
    builtin cd "${rvm_src_path}/rvm/"

    if [[ -z "$(git branch | awk "/$branch$/")" ]]
    then
      if git checkout -b "$branch" --track "$remote/$branch" 2>/dev/null
      then
        log "Successfully checked out branch '$branch'"
      else
        fail "$remote $branch remote branch not found."
      fi
    elif [[ -z "$(git branch | awk "/\* $branch$/{print \$2}")" ]]
    then
      if git checkout $branch 2>/dev/null
      then
        log "Successfully checked out branch '$branch'"
      else
        fail "Unable to checkout branch $branch."
      fi
    fi

    if git pull --rebase $remote $branch
    then
      log "Successfully pulled (rebased) from $remote $branch"
    else
      fail "Failed pull/rebase $remote $branch"
    fi
  else
    builtin cd "${rvm_src_path}"

    if ! git clone --depth 1 git://github.com/wayneeseguin/rvm.git
    then
      if !  git clone https://github.com/wayneeseguin/rvm.git
      then
        fail "Unable to clone the RVM repository, attempted both git:// and https://"
      fi
    fi
  fi

  builtin cd "${rvm_src_path}/rvm/"

  return 0
}

# Tracing, if asked for.
if [[ "$*" =~ --trace ]] || (( ${rvm_trace_flag:-0} > 0 ))
then
  set -o xtrace
  export rvm_trace_flag=1
fi

# Variable initialization, remove trailing slashes if they exist on HOME
true \
  ${rvm_trace_flag:=0} ${rvm_debug_flag:=0} ${rvm_user_install_flag:=0}\
  ${rvm_ignore_rvmrc:=0} HOME="${HOME%%+(\/)}"


if (( rvm_ignore_rvmrc == 0 ))
then
  for rvmrc in /etc/rvmrc "$HOME/.rvmrc"
  do
    if [[ -s "$rvmrc" ]]
    then
      if \grep '^\s*rvm .*$' "$rvmrc" >/dev/null 2>&1
      then
        printf "\nError: $rvmrc is for rvm settings only.\n"
        printf "rvm CLI may NOT be called from within $rvmrc. \n"
        printf "Skipping the loading of $rvmrc\n"
        return 1
      else
        source "$rvmrc"
      fi
    fi
  done
fi

if [[ -z "${rvm_path:-}" ]]
then
  if (( UID == 0 ))
  then
    rvm_path="/usr/local/rvm"
  else
    rvm_path="${HOME}/.rvm"
  fi
fi
export HOME rvm_path

# Parse CLI arguments.
while (( $# > 0 ))
do
  token="$1"
  shift
  case "$token" in

    --trace)
      set -o xtrace
      export rvm_trace_flag=1
      ;;

    --path)
      if [[ -n "${1:-}" ]]
      then
        rvm_path="$1"
        shift
      else
        fail "--path must be followed by a path."
      fi
      ;;

    --branch) # Install RVM from a given branch
      if [[ -n "${1:-}" ]]
      then
        version="head"
        branch="$1"
        shift
      else
        fail "--branch must be followed by a branchname."
      fi
      ;;

    --user-install)
      rvm_user_install_flag=1
      ;;

    --version)
      case "$1" in
        +([[:digit:]]).+([[:digit:]]).+([[:digit:]]))
          version="$1"
          shift
          ;;
        latest|stable)
          version="latest"
          shift
          ;;
        head|master)
          version="head"
          shift
          branch="master"
          ;;
        *)
          fail "--version must be followed by a vaild version number x.y.z"
          ;;
      esac
      ;;

    +([[:digit:]]).+([[:digit:]]).+([[:digit:]]))
      version="$token"
      ;;

    help|usage)
      usage
      exit 0
      ;;
  *)
    usage
    exit 1
    ;;

  esac
done

true "${version:=head}"

if [[ "$rvm_path" != /* ]]
then
  fail "The rvm install path must be fully qualified. Tried $rvm_path"
fi

rvm_src_path="$rvm_path/src"
rvm_archives_path="$rvm_path/archives"
rvm_releases_url="https://rvm.beginrescueend.com/releases"

for dir in "$rvm_src_path" "$rvm_archives_path"
do
  if [[ ! -d "$dir" ]]
  then
    mkdir -p "$dir"
  fi
done

# Perform the actual installation, first we obtain the source using whichever
# means was specified, if any. Defaults to head.
case "${version}" in
  (head)
    install_head
    ;;

  (latest)
    fetch_version
    install_release
    ;;

  (+([[:digit:]]).+([[:digit:]]).+([[:digit:]])) # x.y.z
    install_release
    ;;
  (*)
    fail "Something went wrong, unrecognized version '$version'"
    ;;
esac

# No matter which one we are doing we install the same way, using the RVM
#   installer script.
flags=()
if (( rvm_trace_flag == 1 ))
then
  flags+=("--trace")
fi

if (( rvm_debug_flag == 1 ))
then
  flags+=("--debug")
fi

chmod +x ./scripts/install

# Now we run the RVM installer.
./scripts/install ${flags[*]} --path "$rvm_path"

