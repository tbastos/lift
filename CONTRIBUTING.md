# Contributing to Lift

:+1::tada: First off, thanks for taking the time to contribute! :tada::+1:

The following is a set of guidelines for contributing to Lift on GitHub.
These are just guidelines, not rules, use your best judgment and feel free to
propose changes to this document in a pull request.

## Submitting Issues

* Include the version of Lift you are using, the OS, and as many details as
  possible with your report.
* Check the [debugging guide](#debugging) below for tips on debugging.
  You might be able to find the cause of the problem and fix things yourself.
* Include the behavior you expected and other places you've seen that behavior
  such as Rake, NPM, etc.
* Perform a cursory search to see if a similar issue has already been submitted.

## Pull Requests

* Please follow the existing code style.
* Include thoughtfully-worded, well-structured [busted] specs in the `./spec` folder.
* Run `busted` and make sure all tests are passing.
* In your pull request, explain the reason for the proposed change and how it is valuable.
* After your pull request is accepted, please help update any obsoleted documentation.

## Git Commit Messages

* Use the present tense ("Add feature" not "Added feature").
* Use the imperative mood ("Move cursor to..." not "Moves cursor to...").
* Limit the first line to 72 characters or less.
* Reference issues and pull requests liberally.

## Debugging

_Under construction._

## Philosophy

Lift's _raison d'être_ is to promote the development of top-notch tools in Lua,
and thus help the Lua ecosystem to evolve.

Lift stands for _Lua Infrastructure For Tools_.
And it helps your project to fly!

Design priorities are simplicity first, then conciseness and then efficiency.
In line with Lua's philosophy we should offer maximal value, minimal code,
and concise and precise documentation.

[busted]: http://olivinelabs.com/busted
