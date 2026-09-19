# frozen_string_literal: true

# sloplint-judge: rules whose pattern is a question put to a System One
# model, emitting sloplint Notes. Depends on the sloplint gem; sloplint knows
# this file by name only. See docs/JUDGE.md.
require_relative "version"
require_relative "engine"
require_relative "split"
require_relative "judge/version"
require_relative "judge/rules"
require_relative "judge/backend"
require_relative "judge/engine"
require_relative "judge/compare"
