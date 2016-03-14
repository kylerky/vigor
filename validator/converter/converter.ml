open Core.Std
open Trace_prefix
open Function_spec

type tp = Trace_prefix.trace_prefix

let preamble = In_channel.read_all "preamble.tmpl"

type var_spec = {name: string; t: c_type; v: struct_val option;
                 unique_mention: bool}

type cmplx_val_spec = {name: string; t: c_type; exp: string;}

let allocated_args : var_spec String.Map.t ref = ref String.Map.empty

let infer_signed_type w =
  if String.equal w "w32" then Int
  else failwith (w ^ " signed is not supported")

let infer_unsigned_type w =
  if String.equal w "w32" then Uint32
  else if String.equal w "w16" then Uint16
  else if String.equal w "w8" then Uint8
  else failwith (w ^ " unsigned is not supported")

let infer_type_class f =
  if String.equal f "Sle" then Sunknown
  else if String.equal f "Slt" then Sunknown
  else if String.equal f "Ule" then Uunknown
  else if String.equal f "Ult" then Uunknown
  else Unknown

let get_fun_arg_type fun_name arg_num =
  match String.Map.find fun_types fun_name with
  | Some spec -> List.nth_exn spec.arg_types arg_num
  | None -> failwith ("unknown function " ^ fun_name)

let get_fun_ret_type fun_name = match String.Map.find fun_types fun_name with
  | Some spec -> spec.ret_type
  | None -> failwith ("unknown function " ^ fun_name)

let to_symbol str =
  let no_spaces = String.substr_replace_all str ~pattern:" " ~with_:"_" in
  let no_sharps = String.substr_replace_all no_spaces ~pattern:"#" ~with_:"num" in
  no_sharps

let get_var_name_of_sexp exp =
  match exp with
  | Sexp.List [Sexp.Atom rd; Sexp.Atom w; Sexp.Atom pos; Sexp.Atom name]
    when ( String.equal rd "ReadLSB" ||
           String.equal rd "Read") -> Some (to_symbol name ^ "_" ^
                                            pos(* FIXME: '^ w' - this reveals a bug where
                                               allocated_dmap appears to be w32 and w64*))
  | _ -> None

let get_read_width_of_sexp exp =
  match exp with
  | Sexp.List [Sexp.Atom rd; Sexp.Atom w; Sexp.Atom pos; Sexp.Atom name]
    when (String.equal rd "ReadLSB" ||
          String.equal rd "Read") -> Some w
  | _ -> None

let determine_type t w =
  match t with
  | Sunknown -> infer_signed_type w
  | Uunknown -> infer_unsigned_type w
  | _ -> t

let map_set_n_update_alist mp lst =
  List.fold lst ~init:mp ~f:(fun acc (key,data) ->
      String.Map.add acc ~key ~data)

let is_int str =
  try ignore (int_of_string str); true
  with _ -> false

let guess_type exp =
  match exp with
  | Sexp.Atom str ->
    if (String.equal str "true") ||
       (String.equal str "false") then Bool
    else if is_int str then Int
    else Unknown
  | _ -> Unknown

let rec guess_type_l exps =
  match exps with
  | hd :: tl -> begin match guess_type hd with
      | Unknown -> guess_type_l tl
      | t -> t
    end
  | nil -> Unknown

let merge_var_spec_with_t_and_val (spec:var_spec) t v =
  let t_final = match spec.t with
    | Unknown -> t
    | Sunknown | Uunknown -> if t = Unknown then spec.t else t
    | _ -> spec.t in
  let v_final = match spec.v with
    | Some _ -> spec.v
    | None -> v in
  {name = spec.name;
   t = t_final;
   v = v_final;
   unique_mention = false;}

let rec get_var_decls_of_sexp exp t known_vars =
  match get_var_name_of_sexp exp, get_read_width_of_sexp exp with
  | Some name, Some w ->
    begin match String.Map.find known_vars name with
      | Some spec -> [merge_var_spec_with_t_and_val spec (determine_type t w) None]
      | None -> [{name = name; t = determine_type t w; v = None; unique_mention = true;}]
    end
  | None, None ->
    begin
    match exp with
    | Sexp.List (Sexp.Atom f :: Sexp.Atom w :: tl)
      when (String.equal w "w32") || (String.equal w "w16") || (String.equal w "w8") ->
      let ty = determine_type (infer_type_class f) w in
      (List.join (List.map tl ~f:(fun e -> get_var_decls_of_sexp e ty known_vars)))
    | Sexp.List (Sexp.Atom f :: tl) ->
      let ty = match (infer_type_class f) with
        | Unknown -> begin match guess_type_l tl with
            | Unknown -> t
            | ty -> ty
          end
        | tc -> tc
      in
      List.join (List.map tl ~f:(fun e -> get_var_decls_of_sexp e ty known_vars))
    | _ -> []
    end
  | _,_ -> failwith "inconsistency in get_var_name/get_read_width"

let make_name_alist_from_var_decls (lst: var_spec list) =
  List.map lst ~f:(fun x -> (x.name,x))

let rec get_vars_from_struct_val v ty known_vars =
  match ty with
  | Str (_, fields) ->
    let ftypes = List.map fields ~f:snd in
    if (List.length v.break_down) = 0 then
      known_vars (* TODO: report an error here*)
    else
      List.fold (List.zip_exn v.break_down ftypes) ~init:known_vars
        ~f:(fun acc (v,t)->
          get_vars_from_struct_val v.value t acc)
  | ty ->
    (*TODO: proper type induction here, e.g. Sadd w16 -> SInt16, ....*)
    let decls = get_var_decls_of_sexp v.full ty known_vars in
    map_set_n_update_alist known_vars (make_name_alist_from_var_decls decls)

let get_vars tpref arg_name_gen =
  let get_vars known_vars call =
    let alloc_local_arg addr t v =
      match String.Map.find !allocated_args addr with
      | None ->
        let p_name = arg_name_gen#generate in
        allocated_args := String.Map.add !allocated_args
            ~key:addr ~data:{name = p_name;
                             t = t;
                             v = v;
                             unique_mention = true};
      | Some spec ->
        allocated_args := String.Map.add !allocated_args
            ~key:addr ~data:(merge_var_spec_with_t_and_val spec t v)
    in
    let arg_vars = List.foldi call.args ~init:known_vars
        ~f:(fun i acc arg ->
            let arg_type = get_fun_arg_type call.fun_name i in
            match arg.pointee with
            | Some ptee ->
              begin
                let ptee_type = get_pointee arg_type in
                assert(arg.is_ptr);
                let addr = (Sexp.to_string arg.value.full) in
                alloc_local_arg addr ptee_type ptee.before;
                let before_vars =
                  match ptee.before with
                  | Some v -> get_vars_from_struct_val v ptee_type acc
                  | None -> acc in
                match ptee.after with
                | Some v -> get_vars_from_struct_val v ptee_type before_vars
                | None -> before_vars
              end
            | None ->
              assert(not arg.is_ptr);
              get_vars_from_struct_val arg.value arg_type acc)
    in
    let ret_vars = match call.ret with
      | Some ret -> get_vars_from_struct_val
                      ret.value (get_fun_ret_type call.fun_name) arg_vars
      (*TODO: get also ret.pointee vars.*)
      | None -> arg_vars in
    let add_vars_from_ctxt vars ctxt =
      map_set_n_update_alist vars (make_name_alist_from_var_decls
                               (get_var_decls_of_sexp ctxt Bool vars)) in
    let call_ctxt_vars =
      List.fold call.call_context ~f:add_vars_from_ctxt ~init:ret_vars in
    let ret_ctxt_vars =
      List.fold call.ret_context ~f:add_vars_from_ctxt ~init:call_ctxt_vars in
    ret_ctxt_vars
  in
  let hist_vars = (List.fold tpref.history ~init:String.Map.empty
                     ~f:get_vars) in
  let tip_vars = (List.fold tpref.tip_calls ~init:hist_vars
                    ~f:get_vars) in
  tip_vars

let name_gen prefix = object
  val mutable cnt = 0
  method generate =
    cnt <- cnt + 1 ;
    prefix ^ Int.to_string cnt
end

let allocated_complex_vals = ref String.Map.empty
let complex_val_name_gen = name_gen "cmplx"

let tmp_val_name_gen = name_gen "tmp"
let allocated_tmp_vals = ref []

let put_in_int_bounds v =
  let integer_val = Int.of_string v in
  if Int.(integer_val > 2147483647) then
    "(" ^ (Int.to_string (integer_val - 2*2147483648)) ^ ")"
  else
    Int.to_string integer_val

let get_cmplx_val_name exp t =
  let key = Sexp.to_string exp in
  match String.Map.find !allocated_complex_vals key with
  | Some v -> v.name
  | None ->
    let name = complex_val_name_gen#generate in
    allocated_complex_vals :=
      String.Map.add !allocated_complex_vals ~key
        ~data:{name = name;
               t = t;
               exp = key;} ;
    name

let allocate_tmp exp t =
  let name = tmp_val_name_gen#generate in
  allocated_tmp_vals :=
    {name = name; t = t; exp = exp} :: !allocated_tmp_vals;
  name

let rec get_sexp_value exp t =
  match exp with
  | Sexp.Atom v ->
    begin
      match t with
      | Int -> put_in_int_bounds v
      | _ -> v
    end
  | Sexp.List [Sexp.Atom f; Sexp.Atom w; Sexp.Atom offset; src;]
    when (String.equal f "Extract") ->
    (*FIXME: make sure the typetransformation works.*)
    (*FIXME: pass a right type to get_sexp_value and llocate_tmp here*)
    "(" ^ (c_type_to_str t) ^ ")" ^ (allocate_tmp (get_sexp_value src Int) Int)
  | Sexp.List [Sexp.Atom f; Sexp.Atom w; lhs; rhs]
    when (String.equal f "Add") ->
    begin (* Prefer a variable in the left position
          due to the weird VeriFast type inference rules.*)
      match lhs with
      | Sexp.Atom str when is_int str ->
        let ival = int_of_string str in (* avoid overflow *)
        if ival > 2147483648 then
          "(" ^ (get_sexp_value rhs t) ^ " - " ^
          (Int.to_string (2*2147483648 - ival)) ^ ")"
        else
          "(" ^ (get_sexp_value rhs t) ^ " + " ^
          (Int.to_string ival) ^ ")"
      | _ ->
        "(" ^ (get_sexp_value lhs t) ^ " + " ^
        (get_sexp_value rhs t) ^ ")"
    end
  | Sexp.List [Sexp.Atom f; lhs; rhs]
    when (String.equal f "Slt") ->
    (*FIXME: get the actual type*)
    "(" ^ (get_sexp_value lhs Sunknown) ^ " < " ^
    (get_sexp_value rhs Sunknown) ^ ")"
  | Sexp.List [Sexp.Atom f; lhs; rhs]
    when (String.equal f "Sle") ->
    (*FIXME: get the actual type*)
    "(" ^ (get_sexp_value lhs Sunknown) ^ " <= " ^
    (get_sexp_value rhs Sunknown) ^ ")"
  | Sexp.List [Sexp.Atom f; lhs; rhs]
    when (String.equal f "Ule") ->
    (*FIXME: get the actual type*)
    "(" ^ (get_sexp_value lhs Uunknown) ^ " <= " ^
    (get_sexp_value rhs Uunknown) ^ ")"
  | Sexp.List [Sexp.Atom f; lhs; rhs]
    when (String.equal f "Ult") ->
    "(" ^ (get_sexp_value lhs Uunknown) ^ " < " ^
    (get_sexp_value rhs Uunknown) ^ ")"
  | Sexp.List [Sexp.Atom f; lhs; rhs]
    when (String.equal f "Eq") ->
    let ty = guess_type_l [lhs;rhs] in
    "(" ^ (get_sexp_value lhs ty) ^ " == " ^
    (get_sexp_value rhs ty) ^ ")"
  (*| Sexp.List [Sexp.Atom f; Sexp.Atom _; lhs; rhs]
    when (String.equal f "And") ->
    "(" ^ (get_sexp_value lhs Int) ^ " && " ^
    (get_sexp_value rhs Int) ^ ")" *)
  | _ ->
    begin match get_var_name_of_sexp exp with
      | Some name -> name
      | None -> get_cmplx_val_name exp t
    end

let get_struct_val_value valu t =
  match t with
  | Str _ -> begin match get_var_name_of_sexp valu.full with
    | Some name -> name
    | None -> failwith "Inline structure values not supported."
    end
  | _ -> get_sexp_value valu.full t

let rec render_assignment var_name var_value var_type =
  begin match var_type with
    | Str (_, fields) ->
      let fts = List.map fields ~f:snd in
      if (List.length var_value.break_down) = 0 then
        "/*TODO:substructure assignment here*/\n"
        (*FIXME: Klee does not export substructures yet.*)
      else
        String.concat (List.map2_exn var_value.break_down fts ~f:(fun f ft ->
            render_assignment (var_name ^ "." ^ f.name) f.value ft))
    | _ ->
      var_name ^ " = " ^ (get_struct_val_value var_value var_type) ^ ";\n"
  end

let render_vars_declarations ( vars : var_spec list ) =
  List.fold vars ~init:"\n" ~f:(fun acc_str v ->
      match v.t with
      | Unknown | Sunknown | Uunknown ->
        acc_str ^ "//" ^ c_type_to_str v.t ^ " " ^ v.name ^ ";\n"
      | _ ->
        acc_str ^ c_type_to_str v.t ^ " " ^ v.name ^ ";\n")

let render_var_assignments ( vars : var_spec list ) =
  List.fold vars ~init:"\n" ~f:(fun acc_str v ->
      match v.v with
      | Some value -> acc_str ^ (render_assignment v.name value v.t)
      | None -> "")

let rec render_eq_sttmt ~is_assert out_arg out_val out_t vars =
  let head = (if is_assert then "assert" else "assume") in
  match out_t with
  | Str (_, fields) -> let f_types = List.map fields ~f:snd in
    if (List.length out_val.break_down) = 0 then
      "/*TODO:substructure equality here*/\n"
      (*FIXME: Klee does not export substructures yet.*)
    else
    String.concat (List.map2_exn out_val.break_down f_types ~f:(fun f ft ->
        render_eq_sttmt ~is_assert (out_arg ^ "." ^ f.name) f.value ft vars))
  | _ ->
    let value = (get_struct_val_value out_val out_t) in
    (match String.Map.find vars value with
     | Some spec when spec.unique_mention ->
       value ^ " = " ^ out_arg ^
       ";//No mention means I can choose the value freely.\n"
     | _ -> "") ^
    "//@ " ^ head ^ "(" ^ out_arg ^ " == " ^ (get_struct_val_value out_val out_t) ^ ");\n"

let render_fun_call_preamble call args =
  let pre_lemmas =
    match String.Map.find fun_types call.fun_name with
    | Some t -> (String.concat ~sep:"\n"
                   (List.map t.lemmas_before ~f:(fun l -> l args)))
    | None -> failwith "" in
  pre_lemmas ^ "\n"

let gen_fun_call_arg_list call =
  List.mapi call.args
      ~f:(fun i arg ->
          let a_type = get_fun_arg_type call.fun_name i in
          ( if arg.is_ptr then
              match arg.pointee with
              | Some ptee ->
                begin
                  if ptee.is_fun_ptr then
                    match ptee.fun_name with
                    | Some n -> n
                    | None -> "fun???"
                  else
                    let arg_name = String.Map.find !allocated_args
                        ( Sexp.to_string arg.value.full ) in
                    match arg_name with
                    | Some n -> "&" ^ n.name
                    | None -> "&arg??"
                end
              | None -> "???"
            else
              get_struct_val_value arg.value a_type))

let render_fun_call call ret_var args ~is_tip =
  let arg_list = String.concat ~sep:", " args in
  let fname_with_args = String.concat [call.fun_name; "("; arg_list; ");\n"] in
  let call_with_ret call_body = match call.ret with
    | Some ret ->
      begin
        let t = get_fun_ret_type call.fun_name in
        let ret_val = get_struct_val_value ret.value t in
        let ret_ass = "//@ " ^ (if is_tip then "assert" else "assume") ^
                      "(" ^ ret_var ^ " == " ^ ret_val ^ ");\n" in
        c_type_to_str t ^ " " ^ ret_var ^ " = " ^ call_body ^ ret_ass
      end
    | None -> call_body
  in
  call_with_ret (fname_with_args)

let find_false_eq_sttmts sttmts =
  List.filter sttmts ~f:(fun sttmt ->
      match sttmt with
      | Sexp.List [Sexp.Atom rel; Sexp.Atom lhs; rhs] ->
        (String.equal rel "Eq") && (String.equal lhs "false")
      | _ -> false)

let find_complementary_sttmts sttmts1 sttmts2 =
  let find_from_left sttmts1 sttmts2 =
  List.find_map (find_false_eq_sttmts sttmts1) ~f:(fun sttmt1 ->
      match sttmt1 with
      | Sexp.List [Sexp.Atom rel; Sexp.Atom lhs; rhs]
        when (String.equal rel "Eq") && (String.equal lhs "false") ->
        List.find sttmts2 ~f:(Sexp.equal rhs)
      | _ -> None)
  in
  match find_from_left sttmts1 sttmts2 with
  | Some st -> Some st
  | None -> find_from_left sttmts2 sttmts1

let render_2tip_call fst_tip snd_tip ret_var args =
  let arg_list = String.concat ~sep:", " args in
  let fname_with_args = String.concat [fst_tip.fun_name; "("; arg_list; ");\n"] in
  let call_with_ret call_body = match fst_tip.ret with
    | Some ret1 ->
      begin
        match snd_tip.ret with
        | Some ret2 ->
          let t = get_fun_ret_type fst_tip.fun_name in
          let ret1_val = get_struct_val_value ret1.value t in
          let ret2_val = get_struct_val_value ret2.value t in
          let ret_ass = "//@ " ^ "assert" ^
                        "(" ^ ret_var ^ " == " ^ ret1_val ^
                        " || " ^ ret_var ^ " == " ^ ret2_val ^
                        ");\n" in
          c_type_to_str t ^ " " ^ ret_var ^ " = " ^ call_body ^ ret_ass
        | None -> failwith "tip call must either allways return or never"
      end
    | None -> call_body
  in
  call_with_ret (fname_with_args)

let render_post_lemmas call ret_name args =
  let post_lemmas =
    match String.Map.find fun_types call.fun_name with
    | Some t -> (String.concat ~sep:"\n"
                   (List.map t.lemmas_after ~f:(fun l -> l ret_name args)))
    | None -> failwith "" in
  post_lemmas

let render_post_statements call ~is_tip vars =
  let sttmts = List.map call.args ~f:(fun arg ->
      if arg.is_ptr then
        match arg.pointee with
        | Some ptee ->
          if ptee.is_fun_ptr then ""
          else begin
            match ptee.after with
            | Some v ->
              let out_arg =
                match String.Map.find !allocated_args (Sexp.to_string arg.value.full) with
                | Some out_arg -> out_arg
                | None -> failwith ( "unknown argument for " ^ (Sexp.to_string arg.value.full))
              in
              render_eq_sttmt ~is_assert:is_tip
                out_arg.name v out_arg.t vars
            | None -> ""
          end
        | None -> ""
      else "") in
  let ret_post_asserts =
    (if is_tip then
       String.concat (List.map call.ret_context ~f:(fun sttmt ->
           "//@ assert(" ^ get_sexp_value sttmt Bool ^ ");\n"))
     else
       "") in
  (String.concat sttmts) ^ ret_post_asserts

let render_fun_call_fabule call ret_name args ~is_tip vars =
  let post_statements = render_post_statements call ~is_tip vars in
  (render_post_lemmas call ret_name args) ^ "\n" ^ post_statements

let render_2tip_call_fabule fst_tip snd_tip ret_name args vars =
  let post_statements_fst_alternative = render_post_statements fst_tip ~is_tip:true vars in
  let post_statements_snd_alternative = render_post_statements snd_tip ~is_tip:true vars in
  let ret_t = get_fun_ret_type fst_tip.fun_name in
  match fst_tip.ret, snd_tip.ret with
  | Some r1, Some r2
    when not (String.equal (get_struct_val_value r1.value ret_t)
                (get_struct_val_value r2.value ret_t))->
    (render_post_lemmas fst_tip ret_name args) ^ "\n" ^
    "if (" ^ ret_name ^ " == " ^ (get_struct_val_value r1.value ret_t) ^ ") {\n" ^
    post_statements_fst_alternative ^ "\n} else {\n" ^
    (render_eq_sttmt ~is_assert:true ret_name r2.value ret_t vars) ^ "\n" ^
    post_statements_snd_alternative ^ "\n}\n"
  | Some _, Some _ -> begin match find_complementary_sttmts
                                      fst_tip.ret_context
                                      snd_tip.ret_context with
      | Some sttmt ->
        let pos_sttmts,neg_sttmts =
          (if List.mem fst_tip.ret_context sttmt then
             post_statements_fst_alternative,
             post_statements_snd_alternative
           else post_statements_snd_alternative,
                post_statements_fst_alternative)
        in
        "if (" ^ (get_sexp_value sttmt Bool) ^ ") {\n" ^
        pos_sttmts ^ "} else {\n" ^
        neg_sttmts ^ "}\n"
      | None -> failwith "tip calls non-differentiated by ret nor\
                          by a complementary condition are not supported"
    end
  | _,_ -> failwith "tip calls non-differentiated by return value not supported."

let render_fun_call_in_context call rname_gen vars =
  let ret_name = (if is_void (get_fun_ret_type call.fun_name) then ""
                 else rname_gen#generate) in
  let args = (gen_fun_call_arg_list call) in
  (render_fun_call_preamble call args) ^
  (render_fun_call call ret_name args ~is_tip:false) ^
  (render_fun_call_fabule call ret_name args ~is_tip:false vars)

let render_tip_call_in_context calls rname_gen vars =
  if List.length calls = 1 then
    let call = List.hd_exn calls in
    let ret_name = (if is_void (get_fun_ret_type call.fun_name) then ""
                    else rname_gen#generate) in
    let args = (gen_fun_call_arg_list call) in
    (render_fun_call_preamble call args) ^
    (render_fun_call call ret_name args ~is_tip:true) ^
    (render_fun_call_fabule call ret_name args ~is_tip:true vars)
  else if List.length calls = 2 then
    let fst_tip = List.hd_exn calls in
    let snd_tip = List.nth_exn calls 1 in
    let ret_name = rname_gen#generate in
    let args = (gen_fun_call_arg_list fst_tip) in
    (*TODO: assert that the inputs of the tip calls are identicall.*)
    (render_fun_call_preamble fst_tip args) ^
    (render_2tip_call fst_tip snd_tip ret_name args) ^
    (render_2tip_call_fabule fst_tip snd_tip ret_name args vars)
  else failwith "0 or too many tip-calls"

let render_function_list tpref vars =
  let rez_gen = name_gen "rez" in
  let hist_funs =
    (List.fold_left tpref.history ~init:""
       ~f:(fun str_acc call ->
           str_acc ^ render_fun_call_in_context call rez_gen vars
         )) in
  let tip_call =
    (render_tip_call_in_context tpref.tip_calls rez_gen vars) in
  hist_funs ^ tip_call

let render_cmplxes () =
  String.concat (List.map (String.Map.data !allocated_complex_vals) ~f:(fun var ->
      ((c_type_to_str var.t) ^ " " ^ var.name ^ ";//") ^
      var.exp ^ "\n"))

let render_tmps () =
  String.concat (List.map (List.rev !allocated_tmp_vals) ~f:(fun var ->
      ((c_type_to_str var.t) ^ " " ^ var.name ^ " = ") ^
      var.exp ^ ";\n"))

let render_context pref =
  let render_ctxt_list l =
    String.concat ~sep:"\n" (List.map l ~f:(fun e ->
        "//@ assume(" ^ (get_sexp_value e Bool) ^ ");"))
  in
  (String.concat ~sep:"\n" (List.map pref.history ~f:(fun call ->
       (render_ctxt_list call.call_context) ^ "\n" ^
       (render_ctxt_list call.ret_context)))) ^ "\n" ^
  (match pref.tip_calls with
   | hd :: tl -> (render_ctxt_list hd.call_context) ^ "\n"
   | nil -> failwith "must have at least one tip call")

let rec get_relevant_segment pref =
  match List.findi pref.history ~f:(fun _ call ->
      String.equal call.fun_name "loop_invariant_consume") with
  | Some (pos,_) ->
    let tail_len = (List.length pref.history) - pos - 1 in
    get_relevant_segment
      {history = List.sub pref.history ~pos:(pos + 1) ~len:tail_len;
       tip_calls = pref.tip_calls;}
  | None -> pref

let render_leaks pref =
  ( String.concat ~sep:"\n" (List.map ( (List.hd_exn pref.tip_calls)::pref.history ) ~f:(fun call ->
      match String.Map.find fun_types call.fun_name with
      | Some t -> String.concat ~sep:"\n" t.leaks
      | None -> failwith "unknown function") ) ^ "\n")

let render_allocated_args () =
  ( String.concat ~sep:"\n" (List.map (String.Map.data !allocated_args)
                               ~f:(fun spec -> (c_type_to_str spec.t) ^ " " ^
                                               (spec.name) ^ ";")))

let render_alloc_args_assignments () =
  List.fold (String.Map.data !allocated_args) ~init:"\n" ~f:(fun acc_str v ->
      match v.v with
      | Some value ->
        acc_str ^ (render_assignment v.name value v.t)
      | None -> "")


let convert_prefix fin cout =
  Out_channel.output_string cout preamble ;
  Out_channel.output_string cout "void to_verify()\
                                  /*@ requires true; @*/ \
                                  /*@ ensures true; @*/\n{\n" ;
  let pref = get_relevant_segment
      (Trace_prefix.trace_prefix_of_sexp (Sexp.load_sexp fin)) in
  let vars = (get_vars pref (name_gen "arg")) in
  let vars_list = String.Map.data vars in
  let var_decls = (render_vars_declarations vars_list) in
  let fun_calls = (render_function_list pref vars) in
  let var_assigns = (render_var_assignments vars_list) in
  let leaks = (render_leaks pref) in
  let context_lemmas = ( render_context pref ) in
  let args_assignments = ( render_alloc_args_assignments ()) in
  Out_channel.output_string cout ( render_cmplxes () );
  Out_channel.output_string cout var_decls;
  Out_channel.output_string cout context_lemmas;
  Out_channel.output_string cout ( render_tmps ());
  Out_channel.output_string cout ( render_allocated_args ());
  Out_channel.output_string cout args_assignments;
  Out_channel.output_string cout var_assigns;
  Out_channel.output_string cout fun_calls;
  Out_channel.output_string cout leaks;
  Out_channel.output_string cout "}\n"

let () =
  Out_channel.with_file Sys.argv.(2) ~f:(fun fout ->
      convert_prefix Sys.argv.(1) fout)