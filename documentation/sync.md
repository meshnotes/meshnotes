When receiving a version tree message, the DocumenManager will save the received versions to the database, and try to merge them with current version.
1. If some versions are already exists, just ignore them.
2. If some versions are not exists, send a "require version" message to other peers to get them.
3. Peers receive a "require version" message, will check if they have the version, and reply with a "provide version" message if they have.
4. After receiving all required versions, the DocumentManager will merge them into current version.

When receiving a version broadcast message, the DocumentManager will check if the received version is already in the database:
1. If so, just ignore it.
2. If not, send a "require version tree" message to other peers to get them, requiring the specific version.
3. Peers receive a "require version tree" message, will check if they have the version, and reply with an entire "version tree" message if they have.
4. Then the same as receiving the version tree message.