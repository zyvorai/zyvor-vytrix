# SPDX-License-Identifier: Apache-2.0
# Homebrew formula stub for the Vytrix collector.
# Fill in `url`/`sha256` from a tagged release before publishing to a tap.
# For an always-on agent with a Keychain-held token, use scripts/install-macos.sh.
class Vytrix < Formula
  desc "Read-only system and container telemetry collector for Zyvor Vytrix"
  homepage "https://github.com/zyvor/zyvor-vytrix"
  url "https://github.com/zyvor/zyvor-vytrix/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "Apache-2.0"

  depends_on "python@3.13"

  def install
    libexec.install "agent/vytrix.py"
    (bin/"vytrix").write <<~SH
      #!/bin/bash
      exec "#{Formula["python@3.13"].opt_bin}/python3.13" "#{libexec}/vytrix.py" "$@"
    SH
  end

  test do
    output = shell_output("#{bin}/vytrix --once --no-containers")
    assert_match "\"version\": 1", output
  end
end
