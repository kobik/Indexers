#!/bin/bash

## Script to keep Prowlarr/Indexers up to date with Jackett/Jackett
## Requirements
### Prowlarr/Indexers git repo exists
### Jackett/Jackett git repo exists
### Require
## Variables
if [[ $1 = "debug" ]]; then
    debug=true
else
    debug=false
fi

prowlarr_git_path="/c/Development/Code/Prowlarr_Indexers/"
jackett_repo_name="z_Jackett/master"
jackett_pulls_branch="jackett-pulls"
prowlarr_commit_template=$(sed -n 1p .gitcommit_pulltemplate.txt)
### Indexer Versions
v1_pattern="v1"
v2_pattern="v2"
v3_pattern="v3"

## Switch to Prowlarr directory and fetch all
cd "$prowlarr_git_path" || exit
git fetch --all
## Config Git and Prevent Conflicts
git config commit.template .gitcommit_pulltemplate.txt
## Check if jackett-pulls exists (remote)
pulls_check=$(git ls-remote --heads origin "$jackett_pulls_branch")
local_pulls_check=$(git branch --list "$jackett_pulls_branch")
if [[ -z "$pulls_check" ]]; then
    ## no existing remote  branch found
    pulls_exists=false
    if [ -n "$local_pulls_check" ]; then
        ## local branch exists
        git branch $jackett_pulls_branch git reset --mixed origin/master
        git branch --unset-upstream
        git checkout -B "$jackett_pulls_branch"
        echo "local $jackett_pulls_branch does exist"
        echo "reset mixed based on origin/master"
        if [[ $debug = true ]]; then
            read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
        fi
    else
        ## local branch does not exist
        ## create new branch from master
        echo "local $jackett_pulls_branch does not exist"
        git checkout -B "$jackett_pulls_branch" origin/master --no-track
        echo "origin/$jackett_pulls_branch created from master"
        if [[ $debug = true ]]; then
            read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
        fi
    fi
else
    ## existing remote branch found
    pulls_exists=true
    echo "$jackett_pulls_branch does exist"
    git checkout -B "$jackett_pulls_branch"
    echo "$jackett_pulls_branch reset out from origin"
    existing_message=$(git log --format=%B -n1)
    if [[ $debug = true ]]; then
        read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
    fi
## pull down recently
fi
jackett_recent_commit=$(git rev-parse "$jackett_repo_name")
echo "most recent jackett commit is: [$jackett_recent_commit] from [$jackett_repo_name]"
recent_pulled_commit=$(git log -n 10 | grep "$prowlarr_commit_template" | awk 'NR==1{print $5}')
## check most recent 10 commits in case we have other commits
echo "most recent jackett commit is: [$recent_pulled_commit] from [origin/$jackett_pulls_branch]"

if [[ $debug = true ]]; then
    read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
fi
## do nothing we are we up to date
if [[ "$jackett_recent_commit" = "$recent_pulled_commit" ]]; then
    echo "we are current with jackett; nothing to do"
    exit 0
fi

## Pull commits between our most recent pull and jackett's latest commit
commit_range=$(git log --reverse --pretty="%H" "$recent_pulled_commit".."$jackett_recent_commit")
commit_count=$(git rev-list --count "$recent_pulled_commit".."$jackett_recent_commit")

## Cherry pick each commit and attempt to resolve common conflicts
echo "Commit Range is: [ $commit_range ]"
echo "There are [$commit_count] commits to cherry-pick"
echo "--------------------------------------------- Begining Cherrypicking ------------------------------"
for pick_commit in ${commit_range}; do
    echo "cherrypicking [$pick_commit]"
    git cherry-pick --no-commit --rerere-autoupdate --allow-empty --keep-redundant-commits "$pick_commit"
    if [[ $debug = true ]]; then
        echo "cherrypicked"
        read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
    fi
    has_conflicts=$(git ls-files --unmerged)
    if [[ -n $has_conflicts ]]; then
        readme_conflicts=$(git diff --cached --name-only | grep "README.md")
        csharp_conflicts=$(git diff --cached --name-only | grep ".cs")
        js_conflicts=$(git diff --cached --name-only | grep ".js")
        html_conflicts=$(git diff --cached --name-only | grep ".html")
        yml_conflicts=$(git diff --cached --name-only | grep ".yml")
        git config merge.directoryRenames true
        git config merge.verbosity 0
        ## Handle Common Conflicts
        echo "conflicts exist"
        if [[ -n $csharp_conflicts ]]; then
            echo "C# & related conflicts exist; removing *.cs*"
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
            git rm --f "*.cs*"
        fi
        if [[ -n $js_conflicts ]]; then
            echo "JS conflicts exist; removing *.js"
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
            git rm --f "*.js"
        fi
        if [[ -n $html_conflicts ]]; then
            echo "html conflicts exist; removing *.html*"
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
            git rm --f "*.html"
        fi
        if [[ -n $readme_conflicts ]]; then
            echo "README conflict exists; using Prowlarr README"
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
            git checkout --ours "README.md"
            git add --f "README.md"
        fi
        if [[ -n $yml_conflicts ]]; then
            echo "YML conflict exists; using and adding jackett yml [$yml_conflicts]"
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
            git checkout --theirs "*.yml"
            git add --f "definitions/**/*.yml" ## Add any new yml definitions
        fi
    fi
    unset has_conflicts
    unset readme_conflicts
    unset csharp_conflicts
    unset yml_conflicts
    git config merge.directoryRenames conflict
    git config merge.verbosity 2
done
echo "--------------------------------------------- completed cherry pick actions ------------------------------"
echo "checking for if indexer backporting for supported versions & moving new indexers or changes is needed"
## Work on  Indexers
# New Indexers
indexers_new=$(git diff --cached --diff-filter=A --name-only | grep ".yml" | grep "$v1_pattern\|$v2_pattern")
# Changes applied to older version
v1_indexers=$(git diff --cached --name-only | grep ".yml" | grep "$v1_pattern")
v2_indexers=$(git diff --cached --diff-filter=M --name-only | grep ".yml" | grep "$v2_pattern")

move_indexers_new="$indexers_new"
depreciated_indexers="$v1_indexers"
changed_supported_indexers="$v2_indexers"
## ID new Version indexers by Regex
v3_regex1="# json (engine|api)"
v3_regex2="(.*)imdbid:"

## Move new in vOld to vNew
### v1 frozen 2021-10-13
### All new indexers to v2 if possible until v3 is in develop
if [[ -n $move_indexers_new ]]; then
    echo "New Indexers detected"
    for indexer in ${move_indexers_new}; do
        indexer_supported=${indexer/$v1_pattern/$v2_pattern}
        indexer_new=${indexer/$v1_pattern/$v3_pattern}
        indexer_new2=${indexer/$v2_pattern/$v3_pattern}
        echo "evaluating [$indexer] added to [$v1_pattern] or [$v2_pattern] for [$v2_pattern] or [$v3_pattern]"
        if [[ -f $indexer ]]; then
            if grep -Eq "$v3_regex1" "$indexer" || grep -Eq "$v3_regex2" "$indexer"; then
                # code if new
                echo "[$indexer] is [$v3_pattern]"
                if [ "$indexer" = "$indexer_new" ]; then
                    moveto_indexer=$indexer_new2
                else
                    moveto_indexer=$indexer_new
                fi
            else
                # code if not v3
                echo "[$indexer] is [$v2_pattern]"
                moveto_indexer=$indexer_supported
            fi
            if [ "$indexer" != "$moveto_indexer" ]; then
                echo "found indexer for [$indexer]....moving to [$moveto_indexer]"
                mv "$indexer" "$moveto_indexer"
                git rm -f "$indexer"
                git add -f "$moveto_indexer"
            fi
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
        else
            echo "[$indexer] already in [$moveto_indexer]"
        fi
    done
    unset indexer
    unset indexer_supported
    unset indexer_new
    unset moveto_indexer
    unset pattern
fi
echo "--------------------------------------------- completed new indexers ---------------------------------------------"
## Copy new changes in vDepreciated to vSupported
### v1 depreciated 2021-10-17
### All new indexers to v2 if possible until v3 is in develop
if [[ -n $depreciated_indexers ]]; then
    echo "Depreciated Indexers with changes detected"
    for indexer in ${depreciated_indexers}; do
        indexer_supported=${indexer/$v1_pattern/$v2_pattern}
        indexer_new=${indexer/$v1_pattern/$v3_pattern}
        indexer_new2=${indexer/$v2_pattern/$v3_pattern}
        echo "evaluating depreciated [$v1_pattern] [$indexer]"
        if [[ -f $indexer ]]; then
            if grep -Eq "$v3_regex1" "$indexer" || grep -Eq "$v3_regex2" "$indexer"; then
                # code if new
                echo "[$indexer] is [$v3_pattern]"
                if [ "$indexer" = "$indexer_new" ]; then
                    moveto_indexer=$indexer_new2
                else
                    moveto_indexer=$indexer_new
                fi
            else
                # code if not v3
                echo "[$indexer] is [$v2_pattern]"
                moveto_indexer=$indexer_supported
            fi
            copyto_indexer=$moveto_indexer
            if [ "$indexer" != "$copyto_indexer" ]; then
                echo "found changes | copying to [$copyto_indexer] and resetting [$indexer]"
                cp "$indexer" "$copyto_indexer"
                git add "$copyto_indexer"
                git checkout @ -f "$indexer"
            fi
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
        fi
    done
    unset indexer
    unset indexer_supported
    unset indexer_new
    unset copyto_indexer
    unset pattern
fi
echo "--------------------------------------------- completed depreciated indexers ---------------------------------------------"
## Check for changes between vSupported that are type vNew
if [[ -n $changed_supported_indexers ]]; then
    echo "Older Indexers with changes detected..."
    for indexer in ${changed_supported_indexers}; do
        indexer_supported=${indexer/$v2_pattern/$v2_pattern}
        indexer_new=${indexer/$v2_pattern/$v3_pattern}
        indexer_new2=${indexer/$v2_pattern/$v3_pattern}
        echo "[$indexer] is changed | evaluate for [$v3_pattern] changes"
        if [[ -f $indexer ]]; then
            if grep -Eq "$v3_regex1" "$indexer" || grep -Eq "$v3_regex2" "$indexer"; then
                # code if new
                echo "[$indexer] is [$v3_pattern]"
                moveto_indexer=$indexer_new
                #if [ "$indexer" = "$indexer_new" ]; then
                #moveto_indexer=$indexer_new2
                #else
                #    moveto_indexer=$indexer_new
                #fi
            else
                # code if not v3
                echo "[$indexer] is [$v2_pattern]"
                moveto_indexer=$indexer_supported
            fi
            copyto_indexer=$moveto_indexer
            if [ "$indexer" != "$copyto_indexer" ]; then
                echo "found changes | copying to [$copyto_indexer] and resetting [$indexer]"
                cp "$indexer" "$copyto_indexer"
                git add "$copyto_indexer"
                git checkout @ -f "$indexer"
            fi
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
        fi
    done
    unset indexer
    unset indexer_supported
    unset indexer_new
    unset copyto_indexer
    unset pattern
fi
echo "--------------------------------------------- completed changed indexers ---------------------------------------------"
## Backport V3 => V2
## No backport V2 => V1 2021-10-23 per Q on discord
backport_indexers=$(git diff --cached --name-only | grep ".yml" | grep "$v3_pattern")
if [[ -n $backport_indexers ]]; then
    for indexer in ${backport_indexers}; do
        backport_indexer=${indexer/$v3_pattern/$v2_pattern} # ToDo - switch to regex and match group conditionals for backporting more than v2 or make a loop
        echo "looking for [$v2_pattern] indexer of [$indexer]"
        if [[ -f $backport_indexer ]]; then
            echo "found [$v2_pattern] indexer for [$indexer]....backporting to [$backport_indexer]"
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
            git difftool --no-index "$indexer" "$backport_indexer"
            git add "$backport_indexer"
        else
            echo "did not find [$v2_pattern] indexer for [$indexer]"
        fi
    done
    unset indexer
    unset backport_indexer
fi
echo "--------------------------------------------- completed backporting indexers ---------------------------------------------"
## Wait for user interaction to handle any conflicts and review
echo "After review; the script will commit the changes."
read -r -p "Press any key to continue or [Ctrl-C] to abort.  Waiting for human review..." -n1 -s
new_commit_msg="$prowlarr_commit_template $jackett_recent_commit"
if [ $pulls_exists = true ]; then
    ## If our branch existed, we squash and ammend
    git merge --squash
    git commit --amend -m "$new_commit_msg" -m "$existing_message"
    echo "Commit Appended"
    # Ask if we should force push
    while true; do
        read -r -p "Do you wish to Force Push with Lease? [Yes/No]:" yn
        case $yn in
        [Yy]*)
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
            git push origin $jackett_pulls_branch --force-if-includes --force-with-lease
            echo "Branch Force Pushed"
            exit 0
            ;;
        [Nn]*) exit 0 ;;
        *) echo "Please answer yes or no." ;;
        esac
    done
else
    ## new branches; new commit
    git commit -m "$new_commit_msg"
    echo "New Commit made"
    # Ask if we should force push
    while true; do
        read -r -p "Do you wish to Push to origin? [Yes/No]:" yn
        case $yn in
        [Yy]*)
            if [[ $debug = true ]]; then
                read -r -p "Pausing for debugging - Press any key to continue or [Ctrl-C] to abort." -n1 -s
            fi
            git push origin $jackett_pulls_branch --force-if-includes --force-with-lease --set-upstream
            echo "Branch Pushed"
            exit 0
            ;;
        [Nn]*) exit 0 ;;
        *) echo "Please answer yes or no." ;;
        esac
    done
fi
