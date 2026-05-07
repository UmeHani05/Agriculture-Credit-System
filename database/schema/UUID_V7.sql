-- this code is imported from https://gist.github.com/edr3x/ba286f20f8bb35205bf750209d621b3b a open source implementation of UUIDv7 in PostgreSQL by Ed R. 
-- UUID V7 vs UUID V4: 
--UUID V7 is a time-based UUID that incorporates a timestamp, 
--while UUID V4 is a random UUID that does not include any time information. 
--UUID V7 provides better performance and scalability for distributed systems, 
--as it allows for efficient generation and sorting of UUIDs based on their creation time. 
--In contrast, UUID V4 can lead to performance issues in distributed systems due to its random nature, 
--which can result in collisions and inefficient indexing.
create or replace function gen_uuidv7() returns uuid as $$
declare
begin
	return gen_uuidv7(clock_timestamp());
end $$ language plpgsql;

create or replace function gen_uuidv7(p_timestamp timestamp with time zone) returns uuid as $$
declare
	v_time   numeric := null;
	v_unix_t numeric := null;
	v_rand_a numeric := null;
	v_rand_b numeric := null;

	v_unix_t_hex varchar := null;
	v_rand_a_hex varchar := null;
	v_rand_b_hex varchar := null;
	v_output_bytes bytea := null;

	c_milli_factor numeric := 10^3::numeric;  -- 1000
	c_micro_factor numeric := 10^6::numeric;  -- 1000000
	c_scale_factor numeric := 4.096::numeric; -- 4.0 * (1024 / 1000)
	
	c_version bit(64) := x'0000000000007000'; -- RFC-4122 version: b'0111...'
	c_variant bit(64) := x'8000000000000000'; -- RFC-4122 variant: b'10xx...'
begin
	v_time := extract(epoch from p_timestamp);

	v_unix_t := trunc(v_time * c_milli_factor);
	v_rand_a := ((v_time * c_micro_factor) - (v_unix_t * c_milli_factor)) * c_scale_factor;
	v_rand_b := random()::numeric * 2^62::numeric;

	v_unix_t_hex := lpad(to_hex(v_unix_t::bigint), 12, '0');
	v_rand_a_hex := lpad(to_hex((v_rand_a::bigint::bit(64) | c_version)::bigint), 4, '0');
	v_rand_b_hex := lpad(to_hex((v_rand_b::bigint::bit(64) | c_variant)::bigint), 16, '0');

	v_output_bytes := decode(v_unix_t_hex || v_rand_a_hex || v_rand_b_hex, 'hex');

	return encode(v_output_bytes, 'hex')::uuid;
end $$ language plpgsql;
