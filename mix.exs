defmodule History.MixProject do
  use Mix.Project

  def project do
    [
      app: :history,
      version: "4.4.22",
      elixir: "~> 1.10",
      description: description(),
      package: package(),
      name: "Improved History",	
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:iex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
     {:ex_doc, "~> 0.28.4", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "Saves shell history and variable bindings between shell sessions.

     Allows the user to display history in a more intuitive and cleaner way than the default.
  
     Historic actions can be viewed, replayed or copied. Scrolling through history is command, not line based."
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/nhpip/history"}
    ]
  end
end
