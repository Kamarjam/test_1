#!/bin/bash

# Check difference between KVM commits in android and linux repositories. 
#Set android repo to version you want to take patches from. Linux version 
#is the version you are applying patches into. So preferrably same.

#$1 path to android repo
#$2 path to linux repo
#$3 output folder

CFD=$(pwd)
LINUX_VERSION_REFERENCE="Linux 6.0" 
ANDROID_REPO=$(readlink -f $1)
LINUX_REPO=$(readlink -f $2)
OUTPATH=$(readlink -f $3)
ANDROID_COMMITS="kvm_commits_sorted_android.txt"
LINUX_COMMITS="kvm_commits_sorted_mainline.txt"
PATCH_LIST="patch.list"
CANDIDATE_LIST="candidate.list"
COMBINED_LIST="combined.list"
COMMITTERS="committers.txt"
BLACKLISTED_CANDIDATES="android-test-infra-autosubmit@system.gserviceaccount.com gregkh@linuxfoundation.org"
BLACKLIST_REGX="kvm\|revert\|selftests\|binder\|gki\|qcom\|KMI"

function get_patches(){
	cd $1
	git rev-parse --git-dir > /dev/null 2>&1
	if [ $? -ne 0 ]; then
	    echo "$1 is not git folder"
	    rm $CFD/$ANDROID_COMMITS > /dev/null 2>&1
		rm $CFD/$LINUX_COMMITS > /dev/null 2>&1
	    exit
	fi

	# Take linux release timestamp as a reference (we are not comparing older commits)
	TIMESTAMP=$(git log  --format=format:"%h %ct %ad %ae \"%s\"" | grep "$LINUX_VERSION_REFERENCE" |  cut -d ' ' -f 2 | head -1)

	# Get all patches that contains kvm (case insensitive) in commit subject
	git log  --reverse --no-merges --format=format:"%h %ct %ce %ad %ae PRIMARY \"%s\"" --after=$TIMESTAMP | grep 'KVM\|kvm' | sed -e '$a\' > kvm_commits.txt

	# Get git commits from folders indicated by MAINTAINERS file (KERNEL VIRTUAL MACHINE FOR ARM64 (KVM/arm64))
	git log  --reverse --no-merges --format=format:"%h %ct %ce %ad %ae PRIMARY \"%s\"" --after=$TIMESTAMP 	arch/arm64/include/asm/kvm* \
																						arch/arm64/include/uapi/asm/kvm* \
																						arch/arm64/kvm/ include/kvm/arm_* \
																						tools/testing/selftests/kvm/*/aarch64/ \
																						tools/testing/selftests/kvm/aarch64/ | sed -e '$a\' >> kvm_commits.txt

	# Remove duplicates by commit hashes and sort by commit time (remaining order if same)
	awk '!seen[$0]++' kvm_commits.txt | sort -b -s -k 2,2 > $CFD/$2
	
	rm kvm_commits.txt
}

function get_candidates(){
	rm $CFD/$CANDIDATE_LIST > /dev/null 2>&1
	cd $1
	while read line;[ -n "$line" ] 
		do
  	  	COMMITTER=${line#* }
  	  	if [[ ! " $BLACKLISTED_CANDIDATES " =~ .*\ $COMMITTER\ .* ]]; then
			git log  --reverse --no-merges --format=format:"%h %ct %ce %ad %ae CANDIDATE \"%s\"" --after=$TIMESTAMP --committer=$COMMITTER | grep -vi $BLACKLIST_REGX | sed -e '$a\' >> $CFD/$CANDIDATE_LIST
  	  	fi
	done < $2
}

function create_patches(){
	mkdir -p $3/KVM
  	mkdir -p $3/CANDIDATES
	
	cd $1
	i=0
	while IFS=' ' read  -r -a VAR;[ -n "$VAR" ] 
	  do
  	    i=$((i+1))
  	    if [ "${VAR[10]}" = "PRIMARY" ]; then 
    		git format-patch -o $3/KVM --start-number $i -1 "${VAR[0]}" > /dev/null 2>&1
		else
    		git format-patch -o $3/CANDIDATES --start-number $i -1 "${VAR[0]}" > /dev/null 2>&1
		fi
	done < "$2"
}

# Take separate commit sets from android and linux repos
echo "Get patches ${ANDROID_REPO}"
get_patches $ANDROID_REPO $ANDROID_COMMITS
echo "Get patches ${LINUX_REPO}"
get_patches $LINUX_REPO $LINUX_COMMITS

# Compare patchsets and take only android side
diff $CFD/$ANDROID_COMMITS $CFD/$LINUX_COMMITS | grep '^<' | cut -d ' ' -f2- > $CFD/$PATCH_LIST
cat $CFD/$PATCH_LIST | awk '{print $3}' |sort|uniq -c|sort -n > $CFD/$COMMITTERS

# create list of possible commits that need to be included
echo "Get candidates ${ANDROID_REPO}"
get_candidates $ANDROID_REPO $CFD/$COMMITTERS

cat $CFD/*.list | awk '!seen[$0]++' | sort -b -s -k 2,2 > $CFD/$COMBINED_LIST

# Extract patches from android repo
echo "Create patches"
create_patches $ANDROID_REPO $CFD/$COMBINED_LIST $OUTPATH

rm $CFD/$ANDROID_COMMITS
rm $CFD/$LINUX_COMMITS
rm $CFD/$COMMITTERS

cd $CFD
