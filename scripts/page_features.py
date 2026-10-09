#!/usr/bin/env python3
"""Stub for #454 commit 1: the tests are written against the contract first."""

GATED_ASSETS = {"pagedjs": "printable"}


def opts_in(value):
    raise NotImplementedError


def carries_the_print_layout(printable, visible, print_pdf_button):
    raise NotImplementedError


def typed_name(value):
    raise NotImplementedError


def resolve_print_pdf(value, printable, visible, media_dir):
    raise NotImplementedError


def install_gated_assets(output_dir, counts, vendor_dir=None, printer=print):
    raise NotImplementedError
