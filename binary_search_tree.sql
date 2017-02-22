
--
-- view with nonproportional font to see binary tree structure
-- 
--
--                    ...> ROOT, no key, left only 
--                    .     /
--                    .    /
--                    .   /
--           .......> p: pile <......
--           .       /        \     .
--           .      /          \    .
--           .     /            \   .
--        h: hospital         w: wave <....
--       /    \                /    \     .
--      /      \              /      \    .
--     /        \            /        \   .
--   null     null        null       z: zoo
--                                   /     \
--                                  /       \   
--                                null      null 
--


drop  table     node;
drop  sequence  root_seq;

create table node 
  ( id         serial   -- primary key, pointer to node
  , up_id      integer  -- points to parent node
  , left_id    integer  -- points to left child node
  , right_id   integer  -- points to right child node
  , key        text     -- key for searching 
  , value      text     -- value stored for key 
  );

create sequence root_seq start -1 increment by -1;


create or replace function new_tree( ) returns integer
AS
$$
  declare
    v_root int;    
  begin
    insert into node ( id , value ) values ( nextval('root_seq') , '--root--') returning id into v_root;
    return v_root;
  end;
$$ language plpgsql;


create or replace function get_root( p_current_id integer ) returns integer
AS
$$
  declare   
    v_root integer;
  begin
      with recursive parent(up_id) as
      (
        select up_id from node where id = p_current_id 
        union
        select   node.up_id from   node , parent where  node.id = parent.up_id  
      )
      select min(up_id) from parent into v_root;
      return v_root;
  end;
$$ language plpgsql;



create or replace function get_value( p_current_id int , p_key text ) returns text
as
$$
  declare
    v_current    node;
    return_value text;
  begin    
    select node.* from node into v_current where id = p_current_id;
 
    case
      when p_current_id is null or p_key is null then  return_value := null;
      when p_key = v_current.key                 then  return_value := v_current.value; 
      when p_current_id < 0                      then  return_value := get_value( v_current.left_id  , p_key );
      when p_key < v_current.key                 then  return_value := get_value( v_current.left_id  , p_key );
      when p_key > v_current.key                 then  return_value := get_value( v_current.right_id , p_key );
    end case;
      return return_value;
  end;
$$ language plpgsql;



create or replace function add_key( p_current_id int , p_key text , p_val text , p_left_id int , p_right_id int ) returns void
as
$$
  declare 
    v_current   node;
    v_tmp_id    integer;
  begin
    select node.* from node into v_current where id = p_current_id;
    case
      when p_current_id is null or p_key is null                      then  null;
      when v_current.id < 0      and v_current.left_id  is not null   then  perform add_key( v_current.left_id  , p_key , p_val , p_left_id , p_right_id );
      when p_key < v_current.key and v_current.left_id  is not null   then  perform add_key( v_current.left_id  , p_key , p_val , p_left_id , p_right_id );
      when p_key > v_current.key and v_current.right_id is not null   then  perform add_key( v_current.right_id , p_key , p_val , p_left_id , p_right_id );
      --
      when p_key = v_current.key then  
          update node set value = p_val where id = v_current.id;                        -- update existing node to new value
      --
      when v_current.id < 0 and v_current.left_id is null then
          insert into node   ( up_id        , key   , value , left_id   , right_id   )  -- add very 1st node left of root node
                      values ( v_current.id , p_key , p_val , p_left_id , p_right_id )
                   returning  node.id into v_tmp_id;
          update node set left_id = v_tmp_id where id = v_current.id;
      --
      when p_key < v_current.key and v_current.left_id  is null then
          insert into node   ( up_id        , key   , value , left_id   , right_id   )  -- and leaf node left of current node
                      values ( v_current.id , p_key , p_val , p_left_id , p_right_id )
                   returning  node.id into v_tmp_id;
          update node set left_id = v_tmp_id where id = v_current.id;
      --
      when p_key > v_current.key and v_current.right_id is null then
          insert into node   ( up_id        , key   , value , left_id   , right_id   )  -- add leaf node right of current node
                      values ( v_current.id , p_key , p_val , p_left_id , p_right_id )
                   returning  node.id into v_tmp_id;
          update node set right_id = v_tmp_id where id = v_current.id;
    end case; 
  end;
$$ language plpgsql;





create or replace function remove_key( p_current_id integer , p_key text ) returns void
as
$$
  declare
    v_current               node;
    v_least_greater_node    node;
  begin
    select  node.*  from node  into v_current      where id = p_current_id       ;   
    --
    case
      when v_current.id is null  then  null;
      when v_current.id < 0      then  perform  remove_key( v_current.left_id  , p_key );
      when p_key < v_current.key then  perform  remove_key( v_current.left_id  , p_key );
      when p_key > v_current.key then  perform  remove_key( v_current.right_id , p_key );
      when p_key = v_current.key then 
        -- if there are 2 children, min child on right subtree replaces current node 
        if v_current.left_id is not null and v_current.right_id is not null   then
            select  *  
              from  node  x 
              into  v_least_greater_node 
             where  x.key = (select min(node.key) from node where node.key > v_current.key);
            --
            perform remove_key( p_current_id , v_least_greater_node.key  );
            update  node
              set   key    =  v_least_greater_node.key  
                ,   value  =  v_least_greater_node.value
              where id  =  p_current_id;  
        else
            delete from node where id = v_current.id;
            -- my parent repoints to my only child, if it exists: (left_child XOR right_child) OR (no_children)  
            update node  set  left_id  = case when left_id  = v_current.id then coalesce(v_current.left_id,v_current.right_id) else left_id  end
                           ,  right_id = case when right_id = v_current.id then coalesce(v_current.left_id,v_current.right_id) else right_id end 
               where     id = v_current.up_id;   
            -- point 1 or 0 children to my parent 
            update node set up_id = v_current.up_id where id in (v_current.left_id,v_current.right_id);
            --
        end if;
    end case; 
  end;
$$ language plpgsql;


------------------
-- Testing code --
------------------
delete from node;
--
do
$$
declare
    new_tree integer;
begin
  new_tree := new_tree();
  ---raise notice 'new_tree=%',new_tree;
  perform add_key(   new_tree   , 'h'    , 'hello'     , null , null );
  perform add_key(   new_tree   , 'h'    , 'Hello!'    , null , null );
  perform add_key(   new_tree   , 'a'    , 'apple'     , null , null );
  perform add_key(   new_tree   , 'c'    , 'car'       , null , null );
  perform add_key(   new_tree   , 'b'    , 'bark'      , null , null );
  perform add_key(   new_tree   , 'i'    , 'integer'   , null , null );
  perform add_key(   new_tree   , 'j'    , 'jump'      , null , null );
  perform add_key(   new_tree   , 'm'    , 'monkey'    , null , null );
  perform add_key(   new_tree   , 'k'    , 'kill'      , null , null );
  perform add_key(   new_tree   , 'o'    , 'opera'     , null , null );
  perform add_key(   new_tree   , 'pass' , 'pass'      , null , null );
  perform add_key(   new_tree   , 'l'    , 'let'       , null , null );
  perform add_key(   new_tree   , 'n'    , 'never'     , null , null );
  perform add_key(   new_tree   , 'a'    , 'Apple!'    , null , null );
  --
  perform add_key(   new_tree   , 'pad'  , 'pad'       , null , null );
  perform add_key(   new_tree   , 'page' , 'page'      , null , null );
  perform add_key(   new_tree   , 'pelt' , 'pelt'      , null , null );
  ----------------------------------------------------
  raise notice 'h=%' , get_value( new_tree , 'h' ) ;
  raise notice 'h=%' , get_value( new_tree , 'h' ) ;
  raise notice 'a=%' , get_value( new_tree , 'a' ) ;
  raise notice 'c=%' , get_value( new_tree , 'c' ) ;
  raise notice 'b=%' , get_value( new_tree , 'b' ) ;
  ----------------------------------------------------
  perform remove_key( new_tree , 'c' );
  perform remove_key( new_tree , 'o' );
end;
$$ language plpgsql;

select * from node order by 1,2,3;



