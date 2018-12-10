# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased
### Added
- Stage definition in Legend.BaseStage with execute/3 & compensate/4 as initializers
and step/4 as the means of traversing stage flow.
- Legend.Stage with callbacks for transaction and compensation and most of the
step logic code complete.
- Legend.ErrorHandler which will take care of non-transaction unexpected results
- Legend.Hook which should allow for a highly extensible abstraction, making
persistence, logging, and metrics possible.
- Legend.Event is the core driver of flow in the Legend.BaseStage.step/4 callback,
which takes the current event (among other parameters) and returns the next event
(among other parameters).
- Legend.Utils contains a handful functions useful to serveral modules (e.g. execute/3)
