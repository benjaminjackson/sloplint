# frozen_string_literal: true

# sloplint-judge: rules whose pattern is a question put to a System One
# model, emitting sloplint Notes. Depends on the sloplint gem; sloplint knows
# this file by name only. See docs/JUDGE.md.
# Everything that crosses the gem boundary goes through the load path, not
# require_relative: installed, the two gems sit in different directories.
require "sloplint"
require "sloplint/split"
require_relative "judge/version"
require_relative "judge/rules"
require_relative "judge/secret"
require_relative "judge/backend"
require_relative "judge/engine"
require_relative "judge/compare"
