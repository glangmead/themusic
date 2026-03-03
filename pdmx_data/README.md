# PDMX corpus importer

The [PDMX corpus](https://github.com/pnlong/PDMX) offers a large number of public domain MusicXML and MIDI files, via MuseScore. These lack clean metadata, so this repo tries to enhance the corpus.

The corpus is filtered to the composers mentioned in my document `2025-10-10-classical-composers.html`, which is discussed in [my blog post](https://greg.langmead.info/posts/2025-10-10-classical-composers/).

To run the enhancers, download the following from the [PDMX corpus Zenodo page](https://zenodo.org/records/15571083):

* data.tar.gz
* metadata.tar.gz
* mid.tar.gz
* mxl.tar.gz
* PDMX.csv

and decompress the `.tar.gz` files, then run `make all`.
