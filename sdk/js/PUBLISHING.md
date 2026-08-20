# Publishing an extension

This guide publishes a JavaScript extension as static files that fvcksubs can
install and update.

## Files users download

Keep extension source and tests in the development repository. Publish these
three generated or reviewed files:

```text
repo.json
manifest.json
bundle.js
```

- `repo.json` is the index URL entered in Addons.
- `manifest.json` declares the extension, providers, catalogs, and network
  permissions.
- `bundle.js` contains the JavaScript executed by the app.

All URLs must use HTTPS when publishing for other users.

## 1. Build the bundle

Place `fvcksubs.js` first, followed by the extension source files in dependency
order. A simple shell build looks like this:

```sh
mkdir -p dist
cat sdk/fvcksubs.js src/catalog.js src/streams.js > dist/bundle.js
cp manifest.json dist/manifest.json
```

For larger extensions, use a project script that produces the same two files.
The app does not download source modules separately; `manifest.entry` must name
the published bundle:

```json
{
  "entry": "bundle.js"
}
```

## 2. Increase the version

Change `manifest.json.version` whenever published behavior or metadata changes:

```json
{
  "version": "1.2.0"
}
```

Use dotted integers such as `1.2.0`. The app compares each segment numerically.
The version in `repo.json` must exactly match the manifest version.

## 3. Calculate the bundle SHA-256

The hash covers the exact bytes of the published `bundle.js`. Recalculate it
after every bundle change.

macOS:

```sh
shasum -a 256 dist/bundle.js
```

Linux:

```sh
sha256sum dist/bundle.js
```

Windows PowerShell:

```powershell
(Get-FileHash .\dist\bundle.js -Algorithm SHA256).Hash.ToLower()
```

Node.js, on any supported platform:

```sh
node -e "const fs=require('fs'),c=require('crypto');process.stdout.write(c.createHash('sha256').update(fs.readFileSync('dist/bundle.js')).digest('hex')+'\n')"
```

The command returns a 64-character lowercase hexadecimal value:

```text
2b14f9eaa5f6c1c82d25d68fd9c33b01d1ad4a77687e67e95ea364f19f61f3d2
```

Copy that value into `repo.json.bundleSha256` without the filename or extra
spaces.

## 4. Create repo.json

Start from [`example/repo.json`](example/repo.json):

```json
{
  "extensions": [
    {
      "id": "hello",
      "name": "Hello SDK",
      "version": "1.2.0",
      "description": "Example extension.",
      "author": "Example Publisher",
      "hosts": ["cdn.example.com"],
      "releaseNotes": [
        "Added live events.",
        "Fixed stream selection."
      ],
      "manifestUrl": "https://example.com/hello/manifest.json",
      "bundleUrl": "https://example.com/hello/bundle.js",
      "bundleSha256": "2b14f9eaa5f6c1c82d25d68fd9c33b01d1ad4a77687e67e95ea364f19f61f3d2"
    }
  ]
}
```

Required consistency checks:

| `repo.json` value | Must match |
|---|---|
| `id` | `manifest.json.id` |
| `version` | `manifest.json.version` |
| `hosts` | `manifest.json.permissions.hosts` |
| `bundleSha256` | SHA-256 of the published `bundle.js` |

`releaseNotes` is optional. Keep each entry short and describe changes a user
can observe. It does not belong in `manifest.json` or the runtime TypeScript
definitions.

## 5. Publish with a public GitHub repository

The development repository may remain private. Create a separate public
repository containing only the three release files:

```text
extension-release/
├── repo.json
├── manifest.json
└── bundle.js
```

For a repository named `publisher/extension-release`, use these URLs:

```text
https://raw.githubusercontent.com/publisher/extension-release/main/repo.json
https://raw.githubusercontent.com/publisher/extension-release/main/manifest.json
https://raw.githubusercontent.com/publisher/extension-release/main/bundle.js
```

Do not put a GitHub token in the app or in an artifact URL. Raw files from a
private repository require authentication and cannot be used as a public
extension index.

Raw GitHub is sufficient for small releases. GitHub Pages or a static CDN is a
better choice when stable caching and traffic control matter. The file format
is identical; only the URLs change.

After creating the empty public repository on GitHub, publish the artifacts:

```sh
git clone git@github.com:publisher/extension-release.git
cp dist/repo.json dist/manifest.json dist/bundle.js extension-release/
cd extension-release
git add repo.json manifest.json bundle.js
git commit -m "release: publish extension 1.2.0"
git push -u origin main
```

For later versions, copy the rebuilt files into the same checkout, commit, and
push again. Do not copy source files, test fixtures, credentials, or local
configuration into the public release repository.

## 6. Verify the published files

Download the public bundle and calculate its hash again. This catches an old
file, changed line endings, or an incorrect upload.

macOS:

```sh
curl -fsSL https://example.com/hello/bundle.js | shasum -a 256
```

Linux:

```sh
curl -fsSL https://example.com/hello/bundle.js | sha256sum
```

Check the public index:

```sh
curl -fsSL https://example.com/repo.json
```

Confirm that:

- the public bundle hash equals `bundleSha256`;
- the manifest and index versions match;
- every manifest and bundle URL returns HTTP 200;
- every API, image, subtitle, license, and redirect host used by the extension
  is declared in `permissions.hosts`.

## 7. Install and update

In fvcksubs:

1. Open Addons.
2. Paste the public `repo.json` URL into Repository URL.
3. Select Check.
4. Review permissions and select Install.

For the next release:

1. Update the extension code.
2. Increase the manifest version.
3. Rebuild `bundle.js`.
4. Calculate a new SHA-256.
5. Update `repo.json` version, release notes, hosts, and hash.
6. Publish all changed artifacts together.
7. Verify the public hash.

After the user selects Check, a newer repository version appears as an update.
The confirmation dialog shows the old and new versions, release notes, and any
new network permissions.

## Common failures

### Hash mismatch

`repo.json.bundleSha256` was calculated from a different bundle. Rebuild,
recalculate the hash, update the index, and publish the bundle and index
together.

### Update does not appear

The repository version is not newer than the installed version, or the public
`repo.json` is still cached. Confirm the public response and increase the
version.

### Manifest ID mismatch

`repo.json.id` and `manifest.json.id` differ. IDs are stable identifiers and
must not be changed to rename an extension.

### Network request blocked

The requested host or a redirect host is missing from
`manifest.json.permissions.hosts`. Add the exact host, increase the version,
rebuild, and publish again.

### Images do not load

Image hosts follow the same allowlist rules as API hosts. Add the image host and
any redirect target to the manifest and mirrored `repo.json.hosts` list.

## Release checklist

- Tests and static analysis pass.
- `bundle.js` was rebuilt from the current source.
- Manifest and repository versions match.
- Repository and manifest host lists match.
- Release notes describe user-visible changes.
- The public bundle hash matches `bundleSha256`.
- The public repository URL installs successfully on a clean app.
