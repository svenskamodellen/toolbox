#!/bin/zsh

cd ../lagstiftning-autoindex

highest_tag=$(git tag -l | grep -E 'v[0-9]+' | sort -V | tail -n 1)
echo "Highest tag: ${highest_tag}"

cd ..

for dir in lagstiftning-arbetsmiljolagen lagstiftning-law lagstiftning-medbestammandelagen lagstiftning-lagen-om-anstallningsskydd lagstiftning-arbetstidslagen; do
  if [ -d "$dir" ]; then
    find "$dir" -type f -exec sh -c 'LC_CTYPE=C sed -i "" -E "s/lagstiftning\/autoindex@v[0-9]+/lagstiftning\/autoindex@${1}/g" "$2"' _ "$highest_tag" {} \;

    cd "$dir"
    if git diff --quiet; then
      echo "No changes in $dir."
    else
      git --no-pager diff
      git commit -am "Bump autoindex to ${highest_tag}"
      git push
    fi
    cd ..
  fi
done
