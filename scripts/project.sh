#!/bin/bash
# Shared source groups, relative to the repository root. Keep build/test wiring here.
mkdir -p .build
xcrun clang -fobjc-arc -isysroot "$paper_sdk" -mmacosx-version-min=14.0 -arch "$paper_arch" -c app/documents/TextRecognition.m -o .build/text-recognition.o
paper_swift+=(-import-objc-header app/documents/TextRecognition.h -framework Vision)
paper_documents=(app/support/PaperError.swift app/filing/FilingTypes.swift app/documents/*.swift .build/text-recognition.o)
paper_application=(app/support/*.swift app/documents/*.swift app/scanning/*.swift app/ui/*.swift app/filing/*.swift .build/text-recognition.o)
