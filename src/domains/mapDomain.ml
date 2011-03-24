open Pretty
module ME = Messages

module type S =
sig
  include Lattice.S
  type key (** The type of the map keys. *)
  type value (** The type of the values. *)

  val add: key -> value -> t -> t
  val remove: key -> t -> t
  val find: key -> t -> value
  val mem: key -> t -> bool
  val iter: (key -> value -> unit) -> t -> unit
  val map: (value -> value) -> t -> t
(*  val mapi: (key -> value -> value) -> t -> t*)
  val fold: (key -> value -> 'a -> 'a) -> t -> 'a -> 'a

  val add_list: (key * value) list -> t -> t
  val add_list_set: key list -> value -> t -> t
  val add_list_fun: key list -> (key -> value) -> t -> t
  val filter_class: int -> t -> t

  val for_all: (key -> value -> bool) -> t -> bool
  val map2: (value -> value -> value) -> t -> t -> t
  val long_map2: (value -> value -> value) -> t -> t -> t
(*  val fold2: (key -> value -> value -> 'a -> 'a) -> t -> t -> 'a -> 'a*)
end

module type Groupable = 
sig
  include Printable.S
  val classify: t -> int
  val class_name: int -> string
end

(* Map structure that keeps keys in such order in which
    they were initially added*)
module ExtendedMap (Dom: Groupable) : Map.S  with
  type key = Dom.t  =
struct
  module M = Map.Make (Dom)
  type key = Dom.t
  type 'a t = 'a Map.Make (Dom).t * Dom.t list

  (* trivial map definitions*)
  let empty = M.empty,[]
  let is_empty a = M.is_empty (fst a)
  let find k m = M.find k (fst m)
  let mem k m = M.mem k (fst m)
  let map f m = M.map f (fst m),snd m
  let mapi f m = M.mapi f (fst m), snd m
  let compare f a b = (M.compare f (fst a) (fst b))
  let equal f a b = M.equal f (fst a) (fst b)

  (* keep initial order of keys *)
  let add k e m =
    M.add k e (fst m),
    if List.mem k (snd m) then
      snd m
    else
      let group a b = (Dom.classify a) - (Dom.classify b) in
      List.stable_sort group (k::(snd m))

  let remove k m =
    M.remove k (fst m),
    List.filter (fun s -> not (Dom.equal s k)) (snd m)

  (* fold map in special stored order*)
  let fold f m n =
    let func k = f k (find k m) in
    List.fold_right func (snd m) n

  (* iter over map in special stored order*)
  let iter (f:key -> 'a -> unit) (m:'a t):unit =
    let key_list = snd m in
    let value_list = List.map (fun n -> find n m) key_list in
    List.iter2 f key_list value_list

end

module PMap (Domain: Groupable) (Range: Lattice.S) =
struct
  module M = Map.Make (Domain)
  include Printable.Std
  type key = Domain.t
  type value = Range.t
  type t = Range.t M.t  (* key -> value  mapping *)

  (* And some braindead definitions, because I would want to do
   * include Map.Make (Domain) with type t = Range.t t *)
  let add = M.add
  let remove = M.remove
  let find = M.find
  let mem = M.mem
  let iter = M.iter
  let map = M.map
  let mapi = M.mapi
  let fold = M.fold
  (* And one less brainy definition *)
  let for_all2 = M.equal
  let equal = for_all2 Range.equal

  exception Done
  let for_all p m = 
    let f key value = if p key value then () else raise Done in
      try iter f m; true with Done -> false

  exception Found of key
  let find_first p m = 
    let f key value = if p key value then raise (Found key) else () in
      try iter f m; raise Not_found with Found x -> x 


  let add_list keyvalues m = 
    List.fold_left (fun acc (key,value) -> add key value acc) m keyvalues

  let add_list_set keys value m = 
    List.fold_left (fun acc key -> add key value acc) m keys
  
  let add_list_fun keys f m =
    List.fold_left (fun acc key -> add key (f key) acc) m keys

  let long_map2 op m1 m2 =
    (* For each key-value pair in m1, we accumulate the merged mapping:  *)
    let f key value acc =
      try (* Here we try to do pointwise operation on the values *)
        add key (op value (find key acc)) acc
      with (* If not there, we just add it *)
        | Not_found -> add key value acc 
    in
      (* we start building from m2 *)
      fold f m1 m2

  let map2 op m1 m2 = 
    (* Similar to the previous, except we ignore elements that only occur in one
     * of the mappings, so we start from an empty map *)
    let f key value acc =
      try add key (op value (find key m2)) acc with 
        | Not_found -> acc
        | Lattice.Unsupported _ -> 
            ME.debug "Ignoring Unsupported!"; acc
    in
      fold f m1 M.empty

  let short _ x = "mapping"
  let isSimple _ = false

  let toXML_f _ mapping =
    let esc = Goblintutil.escape in
    let f (key,st) = 
      match Domain.toXML key with
        | Xml.Element ("Loc",attr,[]) ->
            Xml.Element ("Loc", attr, [Range.toXML st])
        | Xml.Element ("Leaf",attr,[]) ->
            let w = Goblintutil.summary_length - 4 in
            let key_str = Domain.short w key in
            let summary = 
              let st_str = Range.short (w - String.length key_str) st in
          esc key_str ^ " -> " ^ esc st_str in

            let attr = [("text", summary);("id",esc key_str)] in begin
              match Range.toXML st with
                | Xml.Element (_, chattr, children) -> 
                    if Range.isSimple st then Xml.Element ("Leaf", attr, [])
                    else Xml.Element ("Node", attr, children)
                | x -> x
            end
        | _ -> Xml.Element ("Node", [("text",esc (Domain.short 40 key^" -> "^Range.short 40 st))], [Domain.toXML key; Range.toXML st])
    in
    let module IMap = Map.Make (struct type t = int let compare (x:int) (y:int) = Pervasives.compare x y end) in
    let groups = 
      let add_grpd k v m = 
        let group = Domain.classify k in
        IMap.add group ((k,v) :: try IMap.find group m with Not_found -> []) m
      in
      M.fold add_grpd mapping IMap.empty
    in
    let children = 
        let h g (kvs:(Domain.t * Range.t) list) xs = 
          match g = -1 && not !Goblintutil.show_temps with
            | true  -> xs
            | false -> (Xml.Element ("Node", [("text", Domain.class_name g);("id",Domain.class_name g)], List.map f kvs))::xs
        in
        IMap.fold h groups []
    in
    let node_attrs = [("text", esc (short Goblintutil.summary_length mapping));("id","map")] in
      Xml.Element ("Node", node_attrs, children)

  let pretty_f short () mapping = 
    let groups =
      let group_fold key itm gps = 
	let cl = Domain.classify key in
	  match gps with
	    | (a,n) when cl <>  n -> ((cl,(M.add key itm M.empty))::a, cl)
	    | (a,_) -> ((fst (List.hd a),(M.add key itm (snd (List.hd a))))::(List.tl a),cl) in	
	List.rev (fst (fold group_fold mapping ([],min_int))) 
    in      
    let f key st dok = 
      dok ++ (if Range.isSimple st then dprintf "%a -> %a\n" else 
        dprintf "%a -> \n  @[%a@]\n") Domain.pretty key Range.pretty st 
    in
    let group_name a () = text (Domain.class_name a) in
    let pretty_group  map () = fold f map nil in
    let pretty_groups rest map = 
      match (fst map) with
	| 0 ->  rest ++ pretty_group (snd map) ()
	| a -> rest ++ dprintf "@[%t {\n  @[%t@]}@]\n" (group_name a) (pretty_group (snd map)) in 
    let content () = List.fold_left pretty_groups nil groups in
      dprintf "@[%s {\n  @[%t@]}@]" (short 60 mapping) content

  let toXML s  = toXML_f short s

  let pretty () x = pretty_f short () x

  let filter_class g m = 
    fold (fun key value acc -> if Domain.classify key = g then add key value acc else acc) m M.empty 

  let pretty_diff () ((x:t),(y:t)): Pretty.doc = 
    Pretty.dprintf "PMap: %a not leq %a" pretty x pretty y
end


module MapBot (Domain: Groupable) (Range: Lattice.S): S with
  type key = Domain.t and 
  type value = Range.t and 
  type t = Range.t Map.Make(Domain).t =
struct
  include PMap (Domain) (Range)

  let leq m1 m2 = 
    (* For each key-value in m1, the same key must be in m2 with a geq value: *)
    let p key value = 
      try Range.leq value (find key m2) with Not_found -> false
    in
      m1 == m2 || for_all p m1

  let find x m = try find x m with | Not_found -> Range.bot ()
  let top () = Lattice.unsupported "partial map top"
  let bot () = M.empty
  let is_top _ = false
  let is_bot = M.is_empty

  let join m1 m2 = if m1 == m2 then m1 else long_map2 Range.join m1 m2
  let meet m1 m2 = if m1 == m2 then m1 else map2 Range.meet m1 m2
  
  let widen  = long_map2 Range.widen
  let narrow = map2 Range.narrow 

  let pretty_diff () ((m1:t),(m2:t)): Pretty.doc = 
    let p key value = 
      not (try Range.leq value (find key m2) with Not_found -> false)
    in
    let report key v1 v2 =
      Pretty.dprintf "Map: %a =@?@[%a@]"
         Domain.pretty key Range.pretty_diff (v1,v2)
    in
    let diff_key k v = function
      | None   when p k v -> Some (report k v (find k m2))
      | Some w when p k v -> Some (w++Pretty.line++report k v (find k m2))
      | x -> x
    in 
    match fold diff_key m1 None with
      | Some w -> w
      | None -> Pretty.dprintf "No binding grew."
end

module MapTop (Domain: Groupable) (Range: Lattice.S): S with
  type key = Domain.t and 
  type value = Range.t and 
  type t = Range.t Map.Make(Domain).t =
struct
  include PMap (Domain) (Range)

  let leq m1 m2 = 
    (* For each key-value in m2, the same key must be in m1 with a leq value: *)
    let p key value = 
      try Range.leq (find key m1) value with Not_found -> false
    in
      m1 == m2 || for_all p m2

  let find x m = try find x m with | Not_found -> Range.top ()
  let top () = M.empty
  let bot () = Lattice.unsupported "partial map bot"
  let is_top = M.is_empty
  let is_bot _ = false

  let join m1 m2 = if m1 == m2 then m1 else map2 Range.join m1 m2
  let meet m1 m2 = if m1 == m2 then m1 else long_map2 Range.meet m1 m2
  
  let widen  = map2 Range.widen
  let narrow = long_map2 Range.narrow 

  let pretty_diff () ((m1:t),(m2:t)): Pretty.doc = 
    let p key value = 
      not (try Range.leq value (find key m2) with Not_found -> true)
    in
    let report key v1 v2 =
      Pretty.dprintf "Map: %a =@?@[%a@]"
         Domain.pretty key Range.pretty_diff (v1,v2)
    in
    let diff_key k v = function
      | None   when p k v -> Some (report k v (find k m2))
      | Some w when p k v -> Some (w++Pretty.line++report k v (find k m2))
      | x -> x
    in 
    match fold diff_key m1 None with
      | Some w -> w
      | None -> Pretty.dprintf "No binding grew."
end

exception Fn_over_All of string

module MapBot_LiftTop (Domain: Groupable) (Range: Lattice.S): S with
  type key = Domain.t and 
  type value = Range.t (*and 
  type t = [ `Lifted of Range.t ExtendedMap(Domain).t | `Top ] *)= 
struct
  module M = MapBot (Domain) (Range)
  include Lattice.LiftTop (M) 
  
  type key   = M.key
  type value = M.value
  
  let add k v = function
    | `Top -> `Top
    | `Lifted x -> `Lifted (M.add k v x)
    
  let remove k = function
    | `Top -> `Top
    | `Lifted x -> `Lifted (M.remove k x)

  let find k = function
    | `Top -> Range.top ()
    | `Lifted x -> M.find k x
   
  let mem k = function
    | `Top -> true
    | `Lifted x -> M.mem k x

  let map f = function 
    | `Top -> `Top
    | `Lifted x -> `Lifted (M.map f x)

  let add_list xs = function
    | `Top -> `Top
    | `Lifted x -> `Lifted (M.add_list xs x)
  
  let add_list_set ks v = function
    | `Top -> `Top
    | `Lifted x -> `Lifted (M.add_list_set ks v x)
    
  let add_list_fun ks f = function 
    | `Top -> `Top
    | `Lifted x -> `Lifted (M.add_list_fun ks f x)
    
  let filter_class i = function
    | `Top -> `Top
    | `Lifted x -> `Lifted (M.filter_class i x)
  
  let map2 f x y =
    match x, y with
      | `Lifted x, `Lifted y -> `Lifted (M.map2 f x y)
      | _ -> raise (Fn_over_All "map2")

  let long_map2 f x y =
    match x, y with
      | `Lifted x, `Lifted y -> `Lifted (M.map2 f x y)
      | _ -> raise (Fn_over_All "long_map2")
  
  let for_all f = function
    | `Top -> raise (Fn_over_All "for_all")
    | `Lifted x -> M.for_all f x
    
  let iter f = function
    | `Top -> raise (Fn_over_All "iter")
    | `Lifted x -> M.iter f x

  let fold f x a = 
    match x with 
      | `Top -> raise (Fn_over_All "fold")
      | `Lifted x -> M.fold f x a
end

module MapTop_LiftBot (Domain: Groupable) (Range: Lattice.S): S with
  type key = Domain.t and 
  type value = Range.t (*and 
  type t = [ `Lifted of Range.t ExtendedMap(Domain).t | `Top ] *)= 
struct
  module M = MapTop (Domain) (Range)
  include Lattice.LiftBot (M) 
  
  type key   = M.key
  type value = M.value
  
  let add k v = function
    | `Bot -> `Bot
    | `Lifted x -> `Lifted (M.add k v x)
    
  let remove k = function
    | `Bot -> `Bot
    | `Lifted x -> `Lifted (M.remove k x)

  let find k = function
    | `Bot -> Range.top ()
    | `Lifted x -> M.find k x
   
  let mem k = function
    | `Bot -> true
    | `Lifted x -> M.mem k x

  let map f = function 
    | `Bot -> `Bot
    | `Lifted x -> `Lifted (M.map f x)

  let add_list xs = function
    | `Bot -> `Bot
    | `Lifted x -> `Lifted (M.add_list xs x)
  
  let add_list_set ks v = function
    | `Bot -> `Bot
    | `Lifted x -> `Lifted (M.add_list_set ks v x)
    
  let add_list_fun ks f = function 
    | `Bot -> `Bot
    | `Lifted x -> `Lifted (M.add_list_fun ks f x)
    
  let filter_class i = function
    | `Bot -> `Bot
    | `Lifted x -> `Lifted (M.filter_class i x)
  
  let map2 f x y =
    match x, y with
      | `Lifted x, `Lifted y -> `Lifted (M.map2 f x y)
      | _ -> raise (Fn_over_All "map2")

  let long_map2 f x y =
    match x, y with
      | `Lifted x, `Lifted y -> `Lifted (M.map2 f x y)
      | _ -> raise (Fn_over_All "long_map2")
  
  let for_all f = function
    | `Bot -> raise (Fn_over_All "for_all")
    | `Lifted x -> M.for_all f x
    
  let iter f = function
    | `Bot -> raise (Fn_over_All "iter")
    | `Lifted x -> M.iter f x

  let fold f x a = 
    match x with 
      | `Bot -> raise (Fn_over_All "fold")
      | `Lifted x -> M.fold f x a
end