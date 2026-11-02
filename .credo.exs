# Same config in every Livecraft app: if you change it here, change the others.
#
# Nesting and complexity are still reported, but they don't fail `mix credo`
# (exit_status 0) until those functions get refactored.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/", "priv/repo/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      checks: %{
        extra: [
          {Credo.Check.Refactor.Nesting, [exit_status: 0]},
          {Credo.Check.Refactor.CyclomaticComplexity, [exit_status: 0]}
        ]
      }
    }
  ]
}
