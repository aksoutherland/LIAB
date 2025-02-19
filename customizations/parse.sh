# Customizations will be stored as follows, mandatory files marked.
#   CNAME.txt		One-line description, <71 characters, mandatory
#   CNAME.pre		Bash script, runs in phase1
#	CNAME.yum		List of packages to install in phase2
#	CNAME.post		Bash script, runs in phase3
#	CNAME.*			Anything else needed/used by the 'pre' or 'post' scripts
#   CNAME.md5		Checksums of all preceding files, mandatory

# Execution plan:
#  1. Verify that all checksums match, reject any with errors
#  2. Let user pick a customization set (if no argument was given, pick "RHIAB" automatically)
#  3. Run CNAME.pre [set variables, prompt for decryption, etc]
#  4. Continue phase1
#  5. Start phase2
#  6. After normal yum installation, add packages in CNAME.yum
#  7. Start phase3
#  8. After minimal setup steps needed to support PXE-installed workstations, run CNAME.post

ls *.txt > ls.tmp
# "Wait, what are you reading?"  File is specified at the END of the loop.
# This avoids interesting gotchas in how bash handles environment variables.
# http://fog.ccsf.edu/~gboyd/cs160b/online/7-loops2/whileread.html
while read CNAME; do
  CNAME_PLAIN=`basename ${CNAME} .txt`
  # By testing this 'backward', we stay silent if the MD5 file was omitted.
  [ ! -f ${CNAME_PLAIN}.md5 ] || md5sum --quiet -c ${CNAME_PLAIN}.md5 &>/dev/null
  if [ $? -eq 0 ]; then
    CLIST=("${CLIST[@]}" "${CNAME_PLAIN}")
  else
    echo "Checksum problem in ${CNAME_PLAIN}, skipping it."
    sleep 2
  fi
done < ls.tmp

for (( N=0; N < ${#CLIST[@]}; N++ )); do
  let M=N+1
  echo " ${M}. `head -n 1 ${CLIST[${N}]}.txt` "
done

 