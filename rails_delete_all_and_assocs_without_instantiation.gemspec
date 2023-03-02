# gem build rails_delete_all_and_assocs_without_instantiation.gemspec

Gem::Specification.new do |s|
  s.name = %q{rails_delete_all_and_assocs_without_instantiation}
  s.version = "0.0.0"
  s.date = %q{2023-03-02}
  s.authors = ["benjamin.dana.software.dev@gmail.com"]
  s.summary = %q{Non-instantiated way of deleting records with dependencies quickly without instantiation.}
  s.licenses = ['LGPL-3.0-only']
  s.files        = `git ls-files`.split("\n")
  # s.files = [
  #   "lib/cancancan_js.rb",
  #   "lib/cancancan_js/cancancan_export.rb",
  #   "vendor/assets/javascripts/cancancan_js.js",
  # ]
  s.require_paths = ["lib"]
  s.homepage = 'https://github.com/danabr75/rails_delete_all_and_assocs_without_instantiation'
  s.add_runtime_dependency 'rails', '>= 5.0'
  s.add_development_dependency 'rails', '>= 5.0'
  s.required_ruby_version = '>= 2.7'
end