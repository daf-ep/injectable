# Test

Writing isn't finishing. A change is done when it has run, not when it looks right, and "it should work" isn't a state, it's a hypothesis.

This rule comes before writing tests and doesn't replace it. Running it is mandatory, writing a test is a decision.

## The Three Checks

They go from cheapest to slowest, and you don't skip the third one just because the first two are green.

The first is that it compiles and analyzes cleanly. It's the dumbest, most rewarding check there is, because a strict analyzer catches what no careful rereading ever does.

The second is that the existing suite passes. It says nothing about what you just wrote, it only says you haven't broken anything else.

The third is that the path you just wrote gets exercised for real. It's the one that gets skipped, and the only one that speaks to today's work.

## Exercising Isn't Rereading

Rereading your own diff proves nothing, because you're rereading what you meant to write. You have to go through the real entry point, with real inputs.

Exercising for real doesn't cost the same everywhere, and the third check doesn't mean reaching for the most expensive way to exercise a path, it means reaching for the cheapest one that actually exercises it. A path that stays inside a single process usually runs immediately, at no real cost. A path that needs a real network, another machine, or a third-party service costs more to run and fails more often for reasons that have nothing to do with the change. A narrow test built against a faithful double already counts as exercising the path for real, as long as the behavior under test doesn't depend on something only the real dependency provides: scope and cost are two different questions, and a test can be narrow without being a reread of the diff in disguise.

For a command, you run it, with and without its options, and on the cases where it should refuse. A refusal that doesn't refuse is a complete bug. For a function, you call it, from a test or from an entry point. For a fix, you reproduce the defect, confirm it's really there, apply the fix, and confirm it goes away, in that order: a fix applied to a bug never reproduced fixes a hypothesis. For an output, whether it's a generated file, a render, or a message, you look at the result produced, not the code that produces it.

The failing case counts as much as the passing one. Empty input, missing file, incompatible option, an unresponsive terminal: that's where new code breaks, and never on the example you had in mind while writing it.

When the cheapest real way to exercise a path needs a resource the current environment doesn't have, there are two honest moves and no third one. Either reach for a substitute faithful enough to answer the same question and say plainly that it's a substitute, or accept that the path can't be verified here and say that instead. Sliding into a reread of the diff and calling it verification is the move this section exists to rule out.

## Everything the Change Touches Has to Answer

The question isn't whether the new thing works, it's whether everything that depended on what you changed still works. The two have different answers.

The blast radius gets established, it doesn't get guessed. You have to look at who calls the modified symbol, what gets produced from it, what reads it without calling it, like a config, a template, or a contract between two components, and what already exercised it without having been rerun since. A test that already existed before the change is part of that blast radius, not an exception to it: once the change touches it or makes it run again, it answers to the same standard as a test written today, and a test that runs without ever asserting anything meaningful doesn't get a pass for having been there first.

Renaming, moving, and extracting are the trickiest cases. The compiler catches part of it and lets through everything that travels through a string, a file path, or reflection.

An unstable result never gets dismissed on a single observation. Rerun it, or compare it against how the same test behaved before the change, before deciding whether the instability was already there or the change caused it. A test that turns unstable only after the change is not a false positive to explain away, it's exactly the kind of damage this section asks you to catch: a race condition or a shared timing assumption broken by the change often shows up as an intermittent result before it shows up as a clean failure.

## When to Write a Test

When its absence would let the problem come back.

A defect you found calls for one, and it's written before the fix, failing without it. A rule, a refusal, or a limit call for one too, because those paths never get walked by normal use, and nothing will signal the day they stop working. A pure function with branches offers the best return there is, plenty of cases for very little setup. And a behavior you just decided on deserves a test, one that keeps the decision from being undone by accident.

A test only earns the place it takes if it can hold that place on its own. It doesn't depend on real system time without controlling how that time passes, it doesn't depend on the order other tests happen to run in, and it doesn't depend on an external service nobody in the room controls. A test built on real time needs a structural guarantee rather than an accidental one: computing an input relative to the moment it runs is fine only when nothing about the gap between two clock readings can flip the expected result, and the moment that gap matters, the test has to control time instead of hoping it stays out of the way. A test written without this constraint is exactly what turns an intermittent result into a guessing game later, once a change comes through and nobody can tell whether the red is new or the test was always this fragile.

You don't need one when running it says everything: a rename the compiler checks in full, a text change, a move with no behavior change, a tooling setting.

When in doubt, the question is what will catch it if it breaks in six months. When the answer is nobody, the test is warranted.

## When the Project Doesn't Have Tests Yet

The eight-line declaration in `rules.md` assumes a command that runs the tests. When it doesn't exist yet, the second check has nothing to check, and that isn't a break in the rule: a suite that doesn't exist can neither pass nor fail. The first and third stay mandatory exactly as before, the third then happening by hand instead of through a test file.

The lack of infrastructure isn't an excuse to stay quiet about, though. It gets reported like anything you couldn't verify, with the reason when it's known, rather than being worked around in silence.

Writing a project's first test is a heavier decision than adding a test to a suite already there, since it commits to a command, a location, and a convention someone will have to pick up afterward. It follows the same question as "When to Write a Test," what will catch it if it breaks in six months, weighed this time against what it costs to introduce the infrastructure for a single line. A project with no tests therefore doesn't oblige the first change that touches it to give it any.

## A Test Reads Without a Comment

A test file carries none, and `comments.md` says why: what you'd have written as a comment doesn't show up when the suite is red, while the case's name and the assertion message do. A setup that needs an explanation actually needs a named setup function, or a named constant instead of the literal you were about to comment.

## A Test That Can't Fail Tests Nothing

You see it red before you see it green. A test written after the fix that passes on the first try has demonstrated nothing, and it might not verify anything at all.

Written after the fact, it also tends to marry the observed behavior instead of the intended one, bug included, because the output gets copied into the expectation. The expectation gets decided before looking at the result.

## Four Ways to Lie Without Meaning To

Saying tests pass without having run them is the most frequent, and the only one that's free to avoid.

Running part of it and concluding about the whole is another. A green file says nothing about the suite, and a suite green locally says nothing about continuous integration.

Fixing a test instead of the code is the third. When a test fails, the first hypothesis is that the change is wrong, and adjusting the expectation removes the only warning you had.

Treating a high coverage number, or a test that runs the code without asserting anything about what it did, as proof of verification is a fourth. Both are proof of execution dressed up as proof of verification, the same lie as the other three wearing a number instead of a sentence.

## What You Create or Start to Test, You Remove or Stop

Folders, sample projects, temporary files, inputs dropped somewhere to see how the code reacts: all of that gets removed once the check is done, or it becomes a state someone will eventually mistake for real.

The same holds for a service or a container started to run the third check for real rather than against a double: a database, a queue, anything `docker compose up` or an equivalent command brought up only to make this one verification possible. Once the check is done, what got started gets stopped, the same way a file gets removed. The same restraint applies too: you stop only what you started yourself, never a service that was already running before the check began. Stopping someone else's database, or a development stack you don't own, to tidy up after your own check costs far more than the time it saves, and it can drop work in progress that has nothing to do with what you were checking.

And it gets removed by looking at what you're deleting. A broad deletion run in a directory that also holds real work costs far more than the time it saves, especially where nothing is versioned yet. You list before erasing, you name what you erase, and you never erase a pattern.

## What You Report

You say what you ran, and you say what you didn't run.

A check announced but not done is worse than no check, because it transfers confidence with nothing behind it. When part of it couldn't be exercised, for lack of a service, because of an interactive terminal, or a missing platform, you say so with the reason, and you name what's left to verify.

When something fails, you report it with the real output. A failure described from memory loses exactly the detail that would have made it understandable.
