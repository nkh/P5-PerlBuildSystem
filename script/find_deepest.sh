#!/bin/bash
fdfind | perl -pe '$_ = tr[/][/] . "\t" . $_' | sort -rn

