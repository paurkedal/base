(*
   This is the interface to the runtime support for [ppx_hash].

   The [ppx_hash] syntax extension supports: [@@deriving_inline hash][@@@end] and [%hash_fold: TYPE] and
   [%hash: TYPE]

   For type [t] a function [hash_fold_t] of type [Hash.state -> t -> Hash.state] is
   generated.

   The generated [hash_fold_<T>] function is compositional, following the structure of the
   type; allowing user overrides at every level. This is in contrast to ocaml's builtin
   polymorphic hashing [Hashtbl.hash] which ignores user overrides.

   The generator also provides a direct hash-function [hash] (named [hash_<T>] when <T> !=
   "t") of type: [t -> Hash.hash_value] as a wrapper around the hash-fold function.

   The folding hash function can be accessed as [%hash_fold: TYPE]
   The direct hash function can be accessed as [%hash: TYPE]
*)

open! Import0

module Array = Array0
module Char  = Char0
module List  = List0

(** Builtin folding-style hash functions, abstracted over [Hash_intf.S] *)
module Folding (Hash : Hash_intf.S)
  : Hash_intf.Builtin_intf with type state = Hash.state
= struct

  type state = Hash.state
  type 'a folder = state -> 'a -> state

  let hash_fold_unit s () = s

  let hash_fold_int      = Hash.fold_int
  let hash_fold_int64    = Hash.fold_int64
  let hash_fold_float    = Hash.fold_float
  let hash_fold_string   = Hash.fold_string

  let as_int f s x = hash_fold_int s (f x)

  (* This ignores the sign bit on 32-bit architectures, but it's unlikely to lead to
     frequent collisions (min_value colliding with 0 is the most likely one).  *)
  let hash_fold_int32        = as_int Caml.Int32.to_int

  let hash_fold_char         = as_int Char.to_int
  let hash_fold_bool         = as_int (function true -> 1 | false -> 0)

  let hash_fold_nativeint s x = hash_fold_int64 s (Caml.Int64.of_nativeint x)

  let hash_fold_option hash_fold_elem s = function
    | None -> hash_fold_int s 0
    | Some x -> hash_fold_elem (hash_fold_int s 1) x

  let rec hash_fold_list_body hash_fold_elem s list =
    match list with
    | [] -> s
    | x::xs -> hash_fold_list_body hash_fold_elem (hash_fold_elem s x) xs

  let hash_fold_list hash_fold_elem s list =
    (* The [length] of the list must be incorporated into the hash-state so values of
       types such as [unit list] - ([], [()], [();()],..) are hashed differently. *)
    (* The [length] must come before the elements to avoid a violation of the rule
       enforced by Perfect_hash. *)
    let s = hash_fold_int s (List.length list) in
    let s = hash_fold_list_body hash_fold_elem s list in
    s

  let hash_fold_lazy_t hash_fold_elem s x =
    hash_fold_elem s (Caml.Lazy.force x)

  let hash_fold_ref_frozen hash_fold_elem s x = hash_fold_elem s (!x)

  let rec hash_fold_array_frozen_i hash_fold_elem s array i =
    if i = Array.length array
    then s
    else
      let e = Array.unsafe_get array i in
      hash_fold_array_frozen_i hash_fold_elem (hash_fold_elem s e) array (i + 1)

  let hash_fold_array_frozen hash_fold_elem s array =
    hash_fold_array_frozen_i
      (* [length] must be incorporated for arrays, as it is for lists. See comment above *)
      hash_fold_elem (hash_fold_int s (Array.length array)) array 0

end

module F (Hash : Hash_intf.S) :
  Hash_intf.Full
  with type hash_value = Hash.hash_value
   and type state      = Hash.state
   and type seed       = Hash.seed
= struct

  include Hash

  type 'a folder = state -> 'a -> state

  let create ?seed () = reset ?seed (alloc ())

  module Builtin = Folding(Hash)

  let run ?seed folder x =
    Hash.get_hash_value (folder (Hash.reset ?seed (Hash.alloc ())) x)

end

module Internalhash : sig
  include Hash_intf.S
    with type state      = private int (* allow optimizations for immediate type *)
     and type seed       = int
     and type hash_value = int

  external fold_int64     : state -> int64  -> state = "internalhash_fold_int64"  [@@noalloc]
  external fold_int       : state -> int    -> state = "internalhash_fold_int"    [@@noalloc]
  external fold_float     : state -> float  -> state = "internalhash_fold_float"  [@@noalloc]
  external fold_string    : state -> string -> state = "internalhash_fold_string" [@@noalloc]
  external get_hash_value : state -> hash_value      = "internalhash_get_hash_value" [@@noalloc]
end = struct
  let description = "internalhash"

  type state = int
  type hash_value = int
  type seed = int

  external create_seeded  : seed            -> state = "%identity"                   [@@noalloc]
  external fold_int64     : state -> int64  -> state = "internalhash_fold_int64"     [@@noalloc]
  external fold_int       : state -> int    -> state = "internalhash_fold_int"       [@@noalloc]
  external fold_float     : state -> float  -> state = "internalhash_fold_float"     [@@noalloc]
  external fold_string    : state -> string -> state = "internalhash_fold_string"    [@@noalloc]
  external get_hash_value : state -> hash_value      = "internalhash_get_hash_value" [@@noalloc]

  let alloc () = create_seeded 0

  let reset ?(seed=0) _t = create_seeded seed

  module For_tests = struct
    let compare_state = compare
    let state_to_string = string_of_int
  end
end

include F(Internalhash)