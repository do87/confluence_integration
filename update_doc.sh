
set -e;
cat list_of_doc_files_to_update;

while IFS='' read -r line || [[ -n "$line" ]]; do
  DIR=$(dirname "${line}");
  FILE=$(basename "${line}");
  if [ ${DIR:0:5} == "docs/" ]; then
    if [ -f "${DIR}/${FILE}" ]; then

      echo "";
      echo "Handling ${DIR}/${FILE}";
      head -n 4 "${DIR}/${FILE}" > file_top_tmp;
      line1=$(cat ./file_top_tmp | sed -n 1p);
      line2=$(cat ./file_top_tmp | sed -n 2p);
      line3=$(cat ./file_top_tmp | sed -n 3p);
      line4=$(cat ./file_top_tmp | sed -n 4p);

      echo ${line1:22:-2} > tmp_title_file;
      title=$(sed 's/"/\\"/g' tmp_title_file);
      rm tmp_title_file;
      space=${line2:22:-2}
      page_id=${line3:24:-2}
      parent_page_id=${line4:31:-2}

      echo "  Title:          ${title}";
      echo "  Space:          ${space}";
      echo "  Page ID:        ${page_id}";
      echo "  Parent page ID: ${parent_page_id}";

      echo "";

      if [ "$space" == "" ]; then
        echo "Error! Space is not defined";
        exit 1;
      fi;

      if [ "$title" == "" ]; then
        echo "Error! Title is a required field";
        exit 1;
      fi;

      if [ "$page_id" == "" ]; then
        echo "page ID not specified, looking for existing posts with title ${title}";
        findPage=$(curl -u "${CONFLUENCE_CREDS}" -X GET -G \
          --url "${CONFLUENCE_API}/content" \
          -d "spaceKey=${space}" \
          -d "title=${title}" \
          -d "expand=version");

        page_id=$(echo "$findPage" | jq -r .results[0].id);
        page_version=$(echo "$findPage" | jq -r .results[0].version.number);
      else
        echo "Finding version for page ID ${page_id}";
        findPage=$(curl -u "${CONFLUENCE_CREDS}" -X GET -G \
          --url "${CONFLUENCE_API}/content/${page_id}" \
          -d "spaceKey=${space}" \
          -d "expand=version");

        page_id=$(echo "$findPage" | jq -r .id);
        if [ "$page_id" == "" ] || [ "$page_id" == "null" ]; then
          echo "Error! Page ID not found";
          exit 1;
        fi;
        page_version=$(echo "$findPage" | jq -r .version.number);
        if [ "$page_version" == "" ] || [ "$page_version" == "null" ]; then
          echo "Page version not found, using 0";
          page_version=0;
        fi;
      fi;

      sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' ${DIR}/${FILE} > ${DIR}/${FILE}_tmp;
      page_content_escaped=$(sed 's/"/\\"/g' ${DIR}/${FILE}_tmp);
      rm -f ${DIR}/${FILE}_tmp;

      if [ "$page_id" == "" ] || [ "$page_id" == "null" ]; then
        echo "Creating a new page";
        echo "First, finding space main page:";
        findPage=$(curl -u "${CONFLUENCE_CREDS}" -X GET -G \
          --url "${CONFLUENCE_API}/content" \
          -d "spaceKey=${space}");

        parent_page_id=$(echo "$findPage" | jq -r .results[0].id);

        version_command="";
      else
        echo "Updating page id: ${page_id} with version: ${page_version} to version "$((page_version + 1));
        version_command="\"version\": {\"number\":"$((page_version+1))"},";
      fi;


      if [ "$parent_page_id" == "" ] || [ "$parent_page_id" == "null" ]; then
        parent_page_string="";
      else
        parent_page_string="\"ancestors\": [{\"id\": ${parent_page_id}}],";
      fi;

      echo "{
          ${parent_page_string}
          ${version_command}
          \"status\": \"current\",
          \"title\": \"${title}\",
          \"type\": \"page\",
          \"space\":{\"key\":\"${space}\"},
          \"body\": {
              \"storage\": {
                  \"value\": \"<ac:structured-macro ac:name=\\\"markdown\\\" ac:schema-version=\\\"1\\\"><ac:plain-text-body><![CDATA[${page_content_escaped}]]></ac:plain-text-body></ac:structured-macro>\",
                  \"representation\": \"storage\"
              }
          }
      }" > tmp_bin_file.json
      cat tmp_bin_file.json;

      if [ "$page_id" == "" ] || [ "$page_id" == "null" ]; then
        curl -u "${CONFLUENCE_CREDS}" -X POST -D \
          --url "${CONFLUENCE_API}/content/" \
          -H "Content-Type: application/json" \
          -d @tmp_bin_file.json;
      else
        curl -u "${CONFLUENCE_CREDS}" -X PUT -D \
          --url "${CONFLUENCE_API}/content/${page_id}" \
          -H "Content-Type: application/json" \
          -d @tmp_bin_file.json;
      fi;

      rm -f tmp_bin_file.json;

    fi;
  fi;
done < "./list_of_doc_files_to_update";
