# Zip Packaging

Create ORM-ready zip files for each starter pack.

## Steps

For each starter pack category (`enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, `vss`):

1. **Generate schema**
   ```bash
   cd ai-accelerator-tf/schemas && python3 create_final_schema.py <category>
   ```

2. **Review for personal information**
   - Scan the `ai-accelerator-tf/` folder for any personal information (API keys, passwords, personal emails, etc.)
   - Stop and alert the user if anything is found

3. **Clean build artifacts**
   ```bash
   find ai-accelerator-tf -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null
   rm -f ai-accelerator-tf/.terraform.lock.hcl
   ```

4. **Create zip**
   - Zip the contents of `ai-accelerator-tf/` (files must be at zip root, not nested)
   - Name: `<version>_<category>.zip`
   - Place in `release_test_matrix/` folder
   ```bash
   cd ai-accelerator-tf && zip -r ../release_test_matrix/<version>_<category>.zip . -x '*.git*' -x '*__pycache__*' -x '*.pytest_cache*'
   ```

5. Repeat for the next category until all packs are zipped
