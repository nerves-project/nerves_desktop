defmodule NervesDesktopTest do
  use ExUnit.Case, async: true

  describe "version/2" do
    test "appends -dev when the build is not a tagged release" do
      assert NervesDesktop.version(~c"0.1.0", false) == "0.1.0-dev"
    end

    test "leaves the version alone for a tagged release build" do
      assert NervesDesktop.version(~c"0.1.0", true) == "0.1.0"
    end

    test "accepts a binary version" do
      assert NervesDesktop.version("1.2.3", false) == "1.2.3-dev"
    end
  end

  describe "version/0" do
    test "starts with the version from the VERSION file" do
      assert String.starts_with?(NervesDesktop.version(), Mix.Project.config()[:version])
    end

    test "marks the test build as a dev build" do
      assert String.ends_with?(NervesDesktop.version(), "-dev")
    end
  end
end
