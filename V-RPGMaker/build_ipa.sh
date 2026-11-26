#!/usr/bin/env bash
# Push, wait for the cloud build, download the IPA.  Needs git + gh (already in Codespaces).
set -e
git add -A && git commit -m "Build" 2>/dev/null || true
git push
sleep 20
RUN=$(gh run list --workflow=build-ipa.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
rm -f V-RPGMaker.ipa
gh run download "$RUN" -n V-RPGMaker-ipa
echo "Done: $(pwd)/V-RPGMaker.ipa (unsigned - sign with Sideloadly/AltStore)"
