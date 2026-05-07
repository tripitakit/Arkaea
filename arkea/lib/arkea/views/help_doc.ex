defmodule Arkea.Views.HelpDoc do
  @moduledoc """
  Pure helpers to render in-app help documents (USER-MANUAL, DESIGN, etc.)
  from their canonical Markdown source files.

  The simulation root contains both Italian (canonical) and English siblings
  for every long-form doc. The Help live view loads them by short slug
  (`"user-manual"`, `"design"`, `"calibration"`, ...) and renders the
  Markdown to safe HTML via `Earmark`.

  This module stays pure: it only reads files and converts strings. It
  never touches the database or the simulation state.
  """

  @type doc_meta :: %{
          slug: String.t(),
          title: String.t(),
          path: Path.t(),
          summary: String.t()
        }

  @doc_root Path.expand("../../../..", __DIR__)

  # In-app help surfaces only user-facing and scientific reference docs.
  # Planning, refactoring and review documents (UI-*-PLAN, REMEDIATION-PLAN,
  # *-REVIEW*) live in `devel-docs/` and stay outside the help registry —
  # they are developer artefacts, not material for end users.
  @docs [
    %{
      slug: "user-manual",
      title: "User manual",
      path: Path.join(@doc_root, "USER-MANUAL.md"),
      summary: "From player registration to observing arms races and cycle closure."
    },
    %{
      slug: "design",
      title: "Biological model (DESIGN)",
      path: Path.join(@doc_root, "devel-docs/01-DESIGN.md"),
      summary: "Canonical reference for the biological model — 15 design blocks."
    },
    %{
      slug: "design-stress-test",
      title: "DESIGN stress-test — Chronicles of a contested estuary",
      path: Path.join(@doc_root, "devel-docs/02-DESIGN_STRESS-TEST.md"),
      summary:
        "Worked use case threading every design block end-to-end on a single illustrative scenario."
    },
    %{
      slug: "calibration",
      title: "Calibration ranges",
      path: Path.join(@doc_root, "devel-docs/04-CALIBRATION.md"),
      summary: "Parameter ranges with primary-literature provenance for every numeric constant."
    },
    %{
      slug: "comparative-analysis",
      title: "Comparative analysis — vs SLiM / Bacmeta / SimBac",
      path: Path.join(@doc_root, "devel-docs/12-COMPARATIVE-ANALYSIS.md"),
      summary: "How Arkea positions itself against the established evolutionary simulators."
    }
  ]

  @doc "List of available docs (slug, title, path, summary)."
  @spec list() :: [doc_meta()]
  def list, do: @docs

  @doc "Find a doc by slug; nil if not registered."
  @spec find(String.t()) :: doc_meta() | nil
  def find(slug) when is_binary(slug) do
    Enum.find(@docs, fn doc -> doc.slug == slug end)
  end

  @doc """
  Read the Markdown source of a registered doc and render to safe HTML.

  Returns `{:ok, %{html: html, headings: [%{level, text, anchor}]}}` on
  success, `{:error, reason}` if the file is missing or Earmark errors out.

  The headings list is extracted from the rendered AST so the LiveView can
  build an in-page table of contents and the glossary tooltip can
  deep-link to specific sections.
  """
  @spec render(doc_meta()) ::
          {:ok,
           %{
             html: Phoenix.HTML.safe(),
             headings: [%{level: integer(), text: String.t(), anchor: String.t()}]
           }}
          | {:error, term()}
  def render(%{path: path}) do
    with {:ok, raw} <- File.read(path) do
      html =
        case Earmark.as_html(raw,
               breaks: false,
               gfm: true,
               smartypants: false,
               escape: false
             ) do
          {:ok, html, _messages} -> html
          {:error, html, _messages} -> html
        end

      {
        :ok,
        %{
          html: Phoenix.HTML.raw(html),
          headings: extract_headings(raw)
        }
      }
    end
  end

  @doc "Pre-compute the absolute on-disk path so tests can verify presence."
  @spec doc_path(String.t()) :: Path.t() | nil
  def doc_path(slug) do
    case find(slug) do
      %{path: path} -> path
      nil -> nil
    end
  end

  @heading_re Regex.compile!(~S"^(#{1,6})\s+(.+)$", "m")

  defp extract_headings(raw) do
    Regex.scan(@heading_re, raw, capture: :all_but_first)
    |> Enum.map(fn [hashes, text] ->
      %{
        level: String.length(hashes),
        text: String.trim(text),
        anchor: text |> String.trim() |> slugify()
      }
    end)
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
