# JVM — Gradle / Maven

## Gradle
**One pass gives all three numbers.** `./gradlew test --rerun-tasks` (without `--rerun-tasks`, up-to-date checks skip modules and the number is meaningless), then read count and per-test times out of the XML that run just wrote — no second execution:
```
find build -path '*test-results*' -name '*.xml' | xargs grep -ho 'testcase name="[^"]*"[^>]*time="[^"]*"' | sed 's/.*name="\([^"]*\)".*time="\([^"]*\)"/\2\t\1/' | sort -rn | head -50
```
Parallel — `gradle.properties`:
```
org.gradle.parallel=true
org.gradle.caching=true
```
plus in the test task: `maxParallelForks = Runtime.runtime.availableProcessors().intdiv(2) ?: 1`. Build cache is often the bigger win than fork count.
Tier: JUnit 5 `@Tag("slow")`, `test { useJUnitPlatform { excludeTags 'slow' } }`, and a separate `slowTest` task with `includeTags 'slow'`. Gate the exclusion so the union stays runnable — `excludeTags 'slow'` only when `!project.hasProperty('allTests')`, then **union: `./gradlew test -PallTests`**.
One class (`<FILE_CMD>`): `./gradlew test -PallTests --tests 'com.example.FooTest'` — `-PallTests` is what lifts the `excludeTags 'slow'` gate; without it a `@Tag("slow")` method in that class is skipped.
Isolation fallback: `maxParallelForks = 1` on the colliding task; `forkEvery = 1` if static state leaks between classes.
Changed-only: Gradle's incremental build already covers this once caching is on — don't hand-roll it.

## Maven
One pass: `time mvn test`, then per-test times from the reports that run wrote — `grep -h 'Time elapsed' target/surefire-reports/*.txt | sort -rn -k5 | head -50`, and the count from `grep -ho '<testcase ' target/surefire-reports/*.xml | wc -l`.
Parallel: surefire `<parallel>classes</parallel>` with `<threadCount>`, `<forkCount>1C</forkCount>`; module-level `mvn -T 1C test`.
Tier: JUnit 5 tags via surefire `<groups>` / `<excludedGroups>`, with the exclusion in a property so **union: `mvn test -DexcludedGroups=`**.
One class (`<FILE_CMD>`): `mvn test -DexcludedGroups= -Dtest=FooTest` — the empty `-DexcludedGroups=` clears the tag exclusion for that run.
Isolation fallback: `<parallel>none</parallel>`, `<forkCount>1</forkCount>`, `<reuseForks>false</reuseForks>`.

## Slow tail
One shared Testcontainers instance per class or suite, not per test; `@DirtiesContext` is expensive — remove where the context isn't actually dirtied; Spring context caching depends on identical config, so keep test config variants few.

Mutation (follow-up only): PIT.
