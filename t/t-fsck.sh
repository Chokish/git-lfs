#!/usr/bin/env bash

. "$(dirname "$0")/testlib.sh"

begin_test "fsck default"
(
  set -e

  reponame="fsck-default"
  git init $reponame
  cd $reponame

  # Create a commit with some files tracked by git-lfs
  git lfs track *.dat
  echo "test data" > a.dat
  echo "test data 2" > b.dat
  git add .gitattributes *.dat
  git commit -m "first commit"

  [ "Git LFS fsck OK" = "$(git lfs fsck)" ]

  aOid=$(git log --patch a.dat | grep "^+oid" | cut -d ":" -f 2)
  aOid12=$(echo $aOid | cut -b 1-2)
  aOid34=$(echo $aOid | cut -b 3-4)
  if [ "$aOid" != "$(calc_oid_file .git/lfs/objects/$aOid12/$aOid34/$aOid)" ]; then
    echo "oid for a.dat does not match"
    exit 1
  fi

  bOid=$(git log --patch b.dat | grep "^+oid" | cut -d ":" -f 2)
  bOid12=$(echo $bOid | cut -b 1-2)
  bOid34=$(echo $bOid | cut -b 3-4)
  if [ "$bOid" != "$(calc_oid_file .git/lfs/objects/$bOid12/$bOid34/$bOid)" ]; then
    echo "oid for b.dat does not match"
    exit 1
  fi


  echo "CORRUPTION" >> .git/lfs/objects/$aOid12/$aOid34/$aOid

  moved=$(canonical_path "$TRASHDIR/$reponame/.git/lfs/bad")
  expected="$(printf 'objects: corruptObject: a.dat (%s) is corrupt
objects: repair: moving corrupt objects to %s' "$aOid" "$moved")"
  [ "$expected" = "$(git lfs fsck)" ]

  [ -e ".git/lfs/bad/$aOid" ]
  [ ! -e ".git/lfs/objects/$aOid12/$aOid34/$aOid" ]
  [ "$bOid" = "$(calc_oid_file .git/lfs/objects/$bOid12/$bOid34/$bOid)" ]
)
end_test

begin_test "fsck dry run"
(
  set -e

  reponame="fsck-dry-run"
  git init $reponame
  cd $reponame

  # Create a commit with some files tracked by git-lfs
  git lfs track *.dat
  echo "test data" > a.dat
  echo "test data 2" > b.dat
  git add .gitattributes *.dat
  git commit -m "first commit"

  [ "Git LFS fsck OK" = "$(git lfs fsck --dry-run)" ]

  aOid=$(git log --patch a.dat | grep "^+oid" | cut -d ":" -f 2)
  aOid12=$(echo $aOid | cut -b 1-2)
  aOid34=$(echo $aOid | cut -b 3-4)
  if [ "$aOid" != "$(calc_oid_file .git/lfs/objects/$aOid12/$aOid34/$aOid)" ]; then
    echo "oid for a.dat does not match"
    exit 1
  fi

  bOid=$(git log --patch b.dat | grep "^+oid" | cut -d ":" -f 2)
  bOid12=$(echo $bOid | cut -b 1-2)
  bOid34=$(echo $bOid | cut -b 3-4)
  if [ "$bOid" != "$(calc_oid_file .git/lfs/objects/$bOid12/$bOid34/$bOid)" ]; then
    echo "oid for b.dat does not match"
    exit 1
  fi

  echo "CORRUPTION" >> .git/lfs/objects/$aOid12/$aOid34/$aOid

  [ "objects: corruptObject: a.dat ($aOid) is corrupt" = "$(git lfs fsck --dry-run)" ]

  if [ "$aOid" = "$(calc_oid_file .git/lfs/objects/$aOid12/$aOid34/$aOid)" ]; then
    echo "oid for a.dat still matches match"
    exit 1
  fi

  if [ "$bOid" != "$(calc_oid_file .git/lfs/objects/$bOid12/$bOid34/$bOid)" ]; then
    echo "oid for b.dat does not match"
    exit 1
  fi
)
end_test

begin_test "fsck does not fail with shell characters in paths"
(
  set -e

  mkdir '[[path]]'
  cd '[[path]]'
  reponame="fsck-shell-paths"
  git init $reponame
  cd $reponame

  # Create a commit with some files tracked by git-lfs
  git lfs track *.dat
  echo "test data" > a.dat
  echo "test data 2" > b.dat
  git add .gitattributes *.dat
  git commit -m "first commit"

  # Verify that the pack code handles glob patterns properly.
  git gc --aggressive --prune=now

  [ "Git LFS fsck OK" = "$(git lfs fsck)" ]
)
end_test

begin_test "fsck: outside git repository"
(
  set +e
  git lfs fsck 2>&1 > fsck.log
  res=$?

  set -e
  if [ "$res" = "0" ]; then
    echo "Passes because $GIT_LFS_TEST_DIR is unset."
    exit 0
  fi
  [ "$res" = "128" ]
  grep "Not in a Git repository" fsck.log
)
end_test

setup_invalid_pointers () {
  git init $reponame
  cd $reponame

  # Create a commit with some files tracked by git-lfs
  git lfs track *.dat
  echo "test data" > a.dat
  echo "test data 2" > b.dat
  git add .gitattributes *.dat
  git commit -m "first commit"

  git cat-file blob :a.dat | awk '{ sub(/$/, "\r"); print }' >crlf.dat
  base64 /dev/urandom | head -c 1025 > large.dat
  git \
    -c "filter.lfs.process=" \
    -c "filter.lfs.clean=cat" \
    -c "filter.lfs.required=false" \
    add crlf.dat large.dat
  git commit -m "second commit"
}

begin_test "fsck detects invalid pointers"
(
  set -e

  reponame="fsck-pointers"
  setup_invalid_pointers

  set +e
  git lfs fsck >test.log 2>&1
  RET=$?
  git lfs fsck --pointers >>test.log 2>&1
  RET2=$?
  set -e

  [ "$RET" -eq 1 ]
  [ "$RET2" -eq 1 ]
  [ $(grep -c 'pointer: nonCanonicalPointer: Pointer.*was not canonical' test.log) -eq 2 ]
  [ $(grep -c 'pointer: unexpectedGitObject: "large.dat".*should have been a pointer but was not' test.log) -eq 2 ]
)
end_test

begin_test "fsck detects invalid pointers with GIT_OBJECT_DIRECTORY"
(
  set -e

  reponame="fsck-pointers-object-directory"
  setup_invalid_pointers

  head=$(git rev-parse HEAD)
  objdir="$(lfstest-realpath .git/objects)"
  cd ..
  git init "$reponame-2"
  gitdir="$(lfstest-realpath "$reponame-2/.git")"
  GIT_WORK_TREE="$reponame-2" GIT_DIR="$gitdir" GIT_OBJECT_DIRECTORY="$objdir" git update-ref refs/heads/main "$head"
  set +e
  GIT_WORK_TREE="$reponame-2" GIT_DIR="$gitdir" GIT_OBJECT_DIRECTORY="$objdir" git lfs fsck --pointers >test.log 2>&1
  RET=$?
  set -e

  [ "$RET" -eq 1 ]
  grep 'pointer: nonCanonicalPointer: Pointer.*was not canonical' test.log
  grep 'pointer: unexpectedGitObject: "large.dat".*should have been a pointer but was not' test.log
)
end_test

begin_test "fsck does not detect invalid pointers with no LFS objects"
(
  set -e

  reponame="fsck-pointers-none"
  git init "$reponame"
  cd "$reponame"

  echo "# README" > README.md
  git add README.md
  git commit -m "Add README"

  git lfs fsck
  git lfs fsck --pointers
)
end_test

begin_test "fsck does not detect invalid pointers with symlinks"
(
  set -e

  reponame="fsck-pointers-symlinks"
  git init "$reponame"
  cd "$reponame"

  git lfs track '*.dat'

  echo "# Test" > a.dat
  ln -s a.dat b.dat
  git add .gitattributes *.dat
  git commit -m "Add files"

  git lfs fsck
  git lfs fsck --pointers
)
end_test

begin_test "fsck does not detect invalid pointers with negated patterns"
(
  set -e

  reponame="fsck-pointers-none"
  git init "$reponame"
  cd "$reponame"

  cat > .gitattributes <<EOF
*.dat filter=lfs diff=lfs merge=lfs -text
b.dat !filter !diff !merge text
EOF

  echo "# Test" > a.dat
  cp a.dat b.dat
  git add .gitattributes *.dat
  git commit -m "Add files"

  git lfs fsck
  git lfs fsck --pointers
)
end_test

begin_test "fsck operates on specified refs"
(
  set -e

  reponame="fsck-refs"
  setup_invalid_pointers

  git rm -f crlf.dat large.dat
  git commit -m 'third commit'

  git commit --allow-empty -m 'fourth commit'

  # Should succeed.  (HEAD and index).
  git lfs fsck
  git lfs fsck HEAD
  git lfs fsck HEAD^^ && exit 1
  git lfs fsck HEAD^
  git lfs fsck HEAD^..HEAD
  git lfs fsck HEAD^^^..HEAD && exit 1
  git lfs fsck HEAD^^^..HEAD^ && exit 1
  # Make the result of the subshell a success.
  true
)
end_test
