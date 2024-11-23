# Overview
A version is a snapshot of the document and content.
A version has 0 or more parents(which it merged from).
Following the current version all the way back to its parent versions, and the parents of parents, a tree-like structure is formed. That is the version tree.

# When to generate a version tree
Only when the document is changed, a version tree will be generated. But not each change will generate a version tree.
In the following situations, a version tree will be generated:
1. After changed and idle(no input, no change) for 15 seconds
2. When changed and the document is closed, before a new document is opened
3. Before the app is closed
4. When sync button(in the title bar's menu) is clicked

# When to sent
When one of these situations occurs, the current version tree is sent to peers:
1. When a new version tree is generated, and has network peers.
2. For every 30 seconds, broadcast the current version hash to other peers(if there is any). The peers will check require the version tree.

# Deprecate version
Some old versions will be deprecated in order to reduce the size of the version tree.
Currently, if a version is generated from local, and not synced to other peers, and there is a new editing change, it will be overridden by a new version. And the old version will be deprecated and will not disturb other peers.

# Implementation
## Generate version tree
