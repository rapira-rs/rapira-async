<?php
// Fail early if a build uses system PHP or leaves out a PR feature.
foreach ([Io\Poll\Context::class, Io\Poll\TimerHandle::class, Io\Poll\NotifyHandle::class,
          Io\Operation::class, Io\Ring\Engine::class] as $class) {
    if (!class_exists($class)) {
        throw new RuntimeException("Missing PR #23997 class: $class");
    }
}
if (PHP_ZTS || !interface_exists(Io\Hooks\Hooks::class) || !function_exists('Io\Hooks\set_hooks')) {
    throw new RuntimeException('Expected NTS PHP with the PR #23997 IO Hooks API');
}
$ring = new Io\Ring\Engine();
printf("PHP %s (%s), IO Ring backend: %s\n", PHP_VERSION, PHP_DEBUG ? 'debug' : 'release', $ring->getBackend()->name);
