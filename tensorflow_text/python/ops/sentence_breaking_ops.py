# coding=utf-8
# Copyright 2019 TF.Text Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Break sentence ops."""

from tensorflow.python.ops.ragged import ragged_tensor

from tensorflow.python.framework import load_library
from tensorflow.python.platform import resource_loader
gen_sentence_breaking_ops = load_library.load_op_library(resource_loader.get_path_to_datafile('_sentence_breaking_ops.so'))


def sentence_fragments(token_word,
                       token_starts,
                       token_ends,
                       token_properties,
                       input_encoding='UTF-8',
                       errors='replace',
                       replacement_char=0xFFFD,
                       replace_control_characters=False):
  """Find the sentence fragments in a given text.

  A sentence fragment is a potential next sentence determined using
  deterministic heuristics based on punctuation, capitalization, and similar
  text attributes.

  Args:
    token_word: A Tensor (w/ rank=2) or a RaggedTensor (w/ ragged_rank=1)
      containing the token strings.
    token_starts: A Tensor (w/ rank=2) or a RaggedTensor (w/ ragged_rank=1)
      containing offsets where the token starts.
    token_ends: A Tensor (w/ rank=2) or a RaggedTensor (w/ ragged_rank=1)
      containing offsets where the token ends.
    token_properties: A Tensor (w/ rank=2) or a RaggedTensor (w/ ragged_rank=1)
      containing a bitmask.

      The values of the bitmask are:
        0x01 (ILL_FORMED) - Text is ill-formed according to TextExtractor;
          typically applies to all tokens of a paragraph that is too short or
          lacks terminal punctuation.  0x40 (TITLE)
        0x02 (HEADING)
        0x04 (BOLD)
        0x10 (UNDERLINED)
        0x20 (LIST)
        0x80 (EMOTICON)
        0x100 (ACRONYM) - Token was identified by Lexer as an acronym.  Lexer
          identifies period-, hyphen-, and space-separated acronyms: "U.S.",
          "U-S", and "U S". Lexer normalizes all three to "US", but the  token
          word field normalizes only space-separated acronyms.
       0x200 (HYPERLINK) - Indicates that the token (or part of the token) is a
          covered by at least one hyperlink. More information of the hyperlink
          is stored in the first token covered by the hyperlink.
    input_encoding: String name for the unicode encoding that should be used to
      decode each string.
    errors: Specifies the response when an input string can't be converted
      using the indicated encoding. One of:
      * `'strict'`: Raise an exception for any illegal substrings.
      * `'replace'`: Replace illegal substrings with `replacement_char`.
      * `'ignore'`: Skip illegal substrings.
    replacement_char: The replacement codepoint to be used in place of invalid
      substrings in `input` when `errors='replace'`; and in place of C0 control
      characters in `input` when `replace_control_characters=True`.
    replace_control_characters: Whether to replace the C0 control characters
      `(U+0000 - U+001F)` with the `replacement_char`.
  Returns:
    A RaggedTensor of `fragment_start`, `fragment_end`, `fragment_properties`
    and `terminal_punc_token`.

    `fragment_properties` is an int32 bitmask whose values may contain:
       1 = fragment ends with terminal punctuation
       2 = fragment ends with multiple terminal punctuations (e.g.
         "She said what?!")
       3 = Has close parenthesis (e.g. "Mushrooms (they're fungi).")
       4 = Has sentential close parenthesis (e.g. "(Mushrooms are fungi!)"

     `terminal_punc_token` is a RaggedTensor containing the index of terminal
      punctuation token immediately following the last word in the fragment
      -- or index of the last word itself, if it's an acronym (since acronyms
      include the terminal punctuation). index of the terminal punctuation
      token.
  """
  if not isinstance(token_starts, ragged_tensor.RaggedTensor):
    token_starts = ragged_tensor.RaggedTensor.from_tensor(token_starts)
  if not isinstance(token_ends, ragged_tensor.RaggedTensor):
    token_ends = ragged_tensor.RaggedTensor.from_tensor(token_ends)
  if not isinstance(token_word, ragged_tensor.RaggedTensor):
    token_word = ragged_tensor.RaggedTensor.from_tensor(token_word)
  if not isinstance(token_properties, ragged_tensor.RaggedTensor):
    token_properties = ragged_tensor.RaggedTensor.from_tensor(token_properties)

  fragment = gen_sentence_breaking_ops.sentence_fragments(
      errors=errors,
      replacement_char=replacement_char,
      replace_control_characters=replace_control_characters,
      input_encoding=input_encoding,
      row_lengths=token_starts.row_lengths(),
      token_start=token_starts.flat_values,
      token_end=token_ends.flat_values,
      token_word=token_word.flat_values,
      token_properties=token_properties.flat_values)
  start, end, properties, terminal_punc_token, row_lengths = fragment
  return tuple(
      ragged_tensor.RaggedTensor.from_row_lengths(value, row_lengths)
      for value in [start, end, properties, terminal_punc_token])
