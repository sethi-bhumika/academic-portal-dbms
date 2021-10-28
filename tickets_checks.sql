-- check if the faculty is offering that course or not
create or replace function check_instructor_match(f_id varchar, course_id varchar)
    returns boolean as
$$
declare
    current_semester integer;
    current_year     integer;
    ins              varchar;
    instructors      varchar[];
begin
    select semester, year
    from academic_data.semester
    into current_semester, current_year;

    execute (format('select instructors from course_offerings.sem_%s_%s where course_code=%s',
                    current_year, current_semester, course_id)) into instructors;
    -- check in the list of instructors
    foreach ins in array instructors
        loop
            if ins = f_id
            then
                return true;
            end if;
        end loop;
    return false; -- instructor not present in the list
end;
$$ language plpgsql;

-- check if that faculty is the adviser or not
create or replace function check_adviser_match(f_id varchar, roll_num varchar)
    returns boolean as
$$
declare
    student_batch_year integer;
    adviser_f_id       varchar;
begin
    select batch_year from academic_data.student_info where roll_number = roll_num into student_batch_year;
    select adviser_id from academic_data.adviser_info where batch_year = student_batch_year into adviser_f_id;
    if adviser_f_id = f_id
    then
        return true;
    else
        return false;
    end if;
end;
$$ language plpgsql;